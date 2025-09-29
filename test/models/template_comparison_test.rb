# frozen_string_literal: true

require "test_helper"

class TemplateComparisonTest < ActiveSupport::TestCase
  def setup
    @temp_dir = Dir.mktmpdir("unraid_templates")
    @backup_dir = Dir.mktmpdir("unraid_backups")

    Rails.application.config.stubs(:backup_directory).returns(@backup_dir)

    @local_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>duplicati</Name>
        <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
        <Network>bridge</Network>
        <Category>Backup:</Category>
        <WebUI>http://[IP]:[PORT:8200]</WebUI>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="WebUI port" Type="Port" Required="true" Display="always"/>
      </Container>
    XML

    @community_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>duplicati</Name>
        <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
        <Network>host</Network>
        <Category>Backup:</Category>
        <WebUI>http://[IP]:[PORT:8200]/web</WebUI>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="Web interface port" Type="Port" Required="true" Display="always"/>
      </Container>
    XML

    @template_file = File.join(@temp_dir, "duplicati.xml")
    File.write(@template_file, @local_xml)

    @local_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "bridge",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]",
      xml_content: @local_xml,
      local_path: @template_file,
      source: "local",
    )

    @community_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest-community",
      network: "host",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]/web",
      xml_content: @community_xml,
      source: "community",
    )

    @comparison = TemplateComparison.create!(
      local_template: @local_template,
      community_template: @community_template,
      status: "pending",
    )
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    FileUtils.rm_rf(@backup_dir)
  end

  test "should validate presence of status" do
    comparison = TemplateComparison.new(
      local_template: @local_template,
      community_template: @community_template,
      status: nil,
    )

    refute_predicate comparison, :valid?
    assert_includes comparison.errors[:status], "can't be blank"
  end

  test "should validate status inclusion" do
    comparison = TemplateComparison.new(
      local_template: @local_template,
      community_template: @community_template,
      status: "invalid_status",
    )

    refute_predicate comparison, :valid?
    assert_includes comparison.errors[:status], "is not included in the list"
  end

  test "should validate uniqueness of local_template_id scoped to community_template_id" do
    duplicate_comparison = TemplateComparison.new(
      local_template: @local_template,
      community_template: @community_template,
      status: "pending",
    )

    refute_predicate duplicate_comparison, :valid?
    assert_includes duplicate_comparison.errors[:local_template_id], "has already been taken"
  end

  test "should identify pending status correctly" do
    assert_predicate @comparison, :pending?
    refute_predicate @comparison, :reviewed?
    refute_predicate @comparison, :applied?
  end

  test "should identify reviewed status correctly" do
    @comparison.update!(status: "reviewed")

    refute_predicate @comparison, :pending?
    assert_predicate @comparison, :reviewed?
    refute_predicate @comparison, :applied?
  end

  test "should identify applied status correctly" do
    @comparison.update!(status: "applied")

    refute_predicate @comparison, :pending?
    refute_predicate @comparison, :reviewed?
    assert_predicate @comparison, :applied?
  end

  test "should scope pending comparisons correctly" do
    other_local = Template.create!(
      name: "plex",
      repository: "lscr.io/linuxserver/plex:latest",
      network: "bridge",
      category: "MediaApp:",
      xml_content: @local_xml.gsub("duplicati", "plex"),
      source: "local",
    )

    other_community = Template.create!(
      name: "plex",
      repository: "lscr.io/linuxserver/plex:latest-community",
      network: "host",
      category: "MediaApp:",
      xml_content: @community_xml.gsub("duplicati", "plex"),
      source: "community",
    )

    reviewed_comparison = TemplateComparison.create!(
      local_template: other_local,
      community_template: other_community,
      status: "reviewed",
    )

    assert_includes TemplateComparison.pending, @comparison
    refute_includes TemplateComparison.pending, reviewed_comparison
  end

  test "should scope reviewed comparisons correctly" do
    other_local = Template.create!(
      name: "plex",
      repository: "lscr.io/linuxserver/plex:latest",
      network: "bridge",
      category: "MediaApp:",
      xml_content: @local_xml.gsub("duplicati", "plex"),
      source: "local",
    )

    other_community = Template.create!(
      name: "plex",
      repository: "lscr.io/linuxserver/plex:latest-community",
      network: "host",
      category: "MediaApp:",
      xml_content: @community_xml.gsub("duplicati", "plex"),
      source: "community",
    )

    reviewed_comparison = TemplateComparison.create!(
      local_template: other_local,
      community_template: other_community,
      status: "reviewed",
    )

    assert_includes TemplateComparison.reviewed, reviewed_comparison
    refute_includes TemplateComparison.reviewed, @comparison
  end

  test "should scope applied comparisons correctly" do
    applied_local = Template.create!(
      name: "sonarr",
      repository: "lscr.io/linuxserver/sonarr:latest",
      network: "bridge",
      category: "MediaApp:",
      xml_content: @local_xml.gsub("duplicati", "sonarr"),
      source: "local",
    )

    applied_community = Template.create!(
      name: "sonarr",
      repository: "lscr.io/linuxserver/sonarr:latest-community",
      network: "host",
      category: "MediaApp:",
      xml_content: @community_xml.gsub("duplicati", "sonarr"),
      source: "community",
    )

    applied_comparison = TemplateComparison.create!(
      local_template: applied_local,
      community_template: applied_community,
      status: "applied",
    )

    assert_includes TemplateComparison.applied, applied_comparison
    refute_includes TemplateComparison.applied, @comparison
  end

  test "has_differences? should return true when differences exist" do
    @comparison.differences = { "network" => { "local" => "bridge", "community" => "host" } }

    assert_predicate @comparison, :has_differences?
  end

  test "has_differences? should return false when no differences exist" do
    @comparison.differences = {}

    refute_predicate @comparison, :has_differences?

    @comparison.differences = nil

    refute_predicate @comparison, :has_differences?
  end

  test "user_choices_for_field should return correct choice" do
    @comparison.user_choices = { "network" => "community" }

    assert_equal "community", @comparison.user_choices_for_field("network")
    assert_nil @comparison.user_choices_for_field("nonexistent")
  end

  test "set_user_choice should set choice correctly" do
    @comparison.set_user_choice("network", "community")

    assert_equal "community", @comparison.user_choices["network"]

    @comparison.set_user_choice("webui", "local")

    assert_equal "local", @comparison.user_choices["webui"]
    assert_equal "community", @comparison.user_choices["network"]
  end

  test "calculate_differences! should populate differences" do
    assert_nil @comparison.differences
    assert_nil @comparison.last_compared_at

    @comparison.calculate_differences!
    @comparison.reload

    assert_predicate @comparison.differences, :present?
    assert_predicate @comparison.last_compared_at, :present?
    assert_includes @comparison.differences, "network"
  end

  test "apply_changes! should fail when not reviewed" do
    refute @comparison.apply_changes!
  end

  test "apply_changes! should succeed when reviewed with user choices" do
    @comparison.calculate_differences!
    @comparison.update!(
      status: "reviewed",
      user_choices: { "network" => "community" },
    )

    assert @comparison.apply_changes!
    @comparison.reload

    assert_equal "applied", @comparison.status
    assert_predicate @comparison.applied_at, :present?
  end

  test "apply_changes? should return false when not reviewed" do
    refute_predicate @comparison, :apply_changes?
  end

  test "apply_changes? should return true when successfully applied" do
    @comparison.calculate_differences!
    @comparison.update!(
      status: "reviewed",
      user_choices: { "network" => "community" },
    )

    assert_predicate @comparison, :apply_changes?
    @comparison.reload

    assert_equal "applied", @comparison.status
    assert_predicate @comparison.applied_at, :present?
  end

  test "preview_changes should return empty hash when not reviewed" do
    preview = @comparison.preview_changes

    assert_empty(preview)
  end

  test "preview_changes should return preview when reviewed with choices" do
    @comparison.calculate_differences!
    @comparison.update!(
      status: "reviewed",
      user_choices: { "network" => "community" },
    )

    preview = @comparison.preview_changes

    assert_predicate preview, :present?
    assert_predicate preview[:basic_fields], :present?
  end

  test "manual_edit_for_field should return correct edit" do
    @comparison.manual_edits = { "network" => "custom_network" }

    assert_equal "custom_network", @comparison.manual_edit_for_field("network")
    assert_nil @comparison.manual_edit_for_field("nonexistent")
  end

  test "set_manual_edit should set edit correctly" do
    @comparison.set_manual_edit("network", "custom_network")

    assert_equal "custom_network", @comparison.manual_edits["network"]

    @comparison.set_manual_edit("webui", "custom_webui")

    assert_equal "custom_webui", @comparison.manual_edits["webui"]
    assert_equal "custom_network", @comparison.manual_edits["network"]
  end

  test "has_manual_edit? should return true when edit exists" do
    @comparison.manual_edits = { "network" => "custom_network" }

    assert(@comparison.has_manual_edit?("network"))
    refute(@comparison.has_manual_edit?("nonexistent"))
  end

  test "has_manual_edit? should return false when no edits exist" do
    @comparison.manual_edits = {}

    refute(@comparison.has_manual_edit?("network"))

    @comparison.manual_edits = nil

    refute(@comparison.has_manual_edit?("network"))
  end
end
