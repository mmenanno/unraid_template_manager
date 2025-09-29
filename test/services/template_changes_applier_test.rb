# frozen_string_literal: true

require "test_helper"

class TemplateChangesApplierTest < ActiveSupport::TestCase
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
        <WebUI>http://[IP]:[PORT:8200]</WebUI>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="WebUI port" Type="Port" Required="true" Display="always"/>
        <Config Name="Appdata" Target="/config" Default="/mnt/user/appdata/duplicati" Mode="rw" Description="Config files" Type="Path" Required="true" Display="always"/>
      </Container>
    XML

    @community_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>duplicati</Name>
        <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
        <Network>host</Network>
        <WebUI>http://[IP]:[PORT:8200]/web</WebUI>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="Web interface port" Type="Port" Required="true" Display="always"/>
        <Config Name="Appdata" Target="/config" Default="/mnt/user/appdata/duplicati" Mode="rw" Description="Config files" Type="Path" Required="true" Display="always"/>
        <Config Name="Backups" Target="/backups" Default="/mnt/user/backups" Mode="rw" Description="Backup storage" Type="Path" Required="false" Display="always"/>
      </Container>
    XML

    @template_file = File.join(@temp_dir, "duplicati.xml")
    File.write(@template_file, @local_xml)

    @local_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "bridge",
      webui: "http://[IP]:[PORT:8200]",
      xml_content: @local_xml,
      local_path: @template_file,
      source: "local",
    )

    @community_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "host",
      webui: "http://[IP]:[PORT:8200]/web",
      xml_content: @community_xml,
      source: "community",
    )

    @comparison = TemplateComparison.create!(
      local_template: @local_template,
      community_template: @community_template,
      status: "reviewed",
      user_choices: {
        "network" => "community",
        "webui" => "community",
        "config_WebUI" => "community",
        "new_config_Backups" => "community",
      },
    )
    @comparison.calculate_differences!

    @applier = TemplateChangesApplier.new(@comparison)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    FileUtils.rm_rf(@backup_dir)
  end

  test "should validate comparison status" do
    @comparison.update!(status: "pending")
    applier = TemplateChangesApplier.new(@comparison)

    assert_raises(TemplateChangesApplier::ApplyError) do
      applier.apply!
    end
  end

  test "should require user choices" do
    @comparison.update!(user_choices: {})
    applier = TemplateChangesApplier.new(@comparison)

    assert_raises(TemplateChangesApplier::ApplyError) do
      applier.apply!
    end
  end

  test "should backup original template before applying changes" do
    original_content = File.read(@template_file)

    @applier.apply!

    # Check that backup was created
    backup_files = Dir.glob(File.join(@backup_dir, "duplicati_backup_*.xml"))

    assert_equal 1, backup_files.size

    backup_content = File.read(backup_files.first)

    assert_equal original_content, backup_content
  end

  test "should apply user choices to local template" do
    @applier.apply!

    @local_template.reload

    # Basic fields should be updated based on user choices
    assert_equal "host", @local_template.network # community choice
    assert_equal "http://[IP]:[PORT:8200]/web", @local_template.webui # community choice
  end

  test "should update template file with new XML content" do
    @applier.apply!

    updated_content = File.read(@template_file)

    # Should contain community template changes
    assert_includes updated_content, "<Network>host</Network>"
    assert_includes updated_content, "<WebUI>http://[IP]:[PORT:8200]/web</WebUI>"
    assert_includes updated_content, "Web interface port"
    assert_includes updated_content, 'Name="Backups"'
  end

  test "should mark comparison as applied" do
    @applier.apply!

    @comparison.reload

    assert_equal "applied", @comparison.status
    refute_nil @comparison.applied_at
  end

  test "should preview basic field changes" do
    preview = @applier.preview_changes

    assert_predicate preview[:basic_fields], :present?
    assert_equal "bridge", preview[:basic_fields]["Network"][:from]
    assert_equal "host", preview[:basic_fields]["Network"][:to]
  end

  test "should preview config changes" do
    preview = @applier.preview_changes

    assert_predicate preview[:configs], :present?
    assert_includes preview[:configs], "WebUI"
    assert_includes preview[:configs], "Backups"
  end

  test "should generate XML preview" do
    preview = @applier.preview_changes

    assert_predicate preview[:xml_preview], :present?
    assert_includes preview[:xml_preview], "<Network>host</Network>"
  end

  test "should handle XML generation with mixed user choices" do
    # Set mixed choices - some local, some community
    @comparison.update!(user_choices: {
      "network" => "local",        # Keep local bridge
      "webui" => "community",      # Use community WebUI
      "config_WebUI" => "local",   # Keep local WebUI config
      "new_config_Backups" => "community", # Add new config
    })

    @applier.apply!

    updated_content = File.read(@template_file)

    # Should have local network but community WebUI
    assert_includes updated_content, "<Network>bridge</Network>"
    assert_includes updated_content, "<WebUI>http://[IP]:[PORT:8200]/web</WebUI>"
    # Should have local WebUI config description
    assert_includes updated_content, "WebUI port"
    # Should have new Backups config
    assert_includes updated_content, 'Name="Backups"'
  end

  test "should handle file write errors gracefully" do
    # Make file read-only
    File.chmod(0o444, @template_file)

    assert_raises(TemplateChangesApplier::ApplyError) do
      @applier.apply!
    end

    # Comparison should not be marked as applied
    @comparison.reload

    assert_equal "reviewed", @comparison.status
  end

  test "should handle missing template file" do
    File.delete(@template_file)
    @local_template.update!(local_path: "/nonexistent/file.xml")
    applier = TemplateChangesApplier.new(@comparison)

    assert_raises(TemplateChangesApplier::ApplyError) do
      applier.apply!
    end
  end

  test "should create backup directory if it doesn't exist" do
    FileUtils.rm_rf(@backup_dir)

    refute Dir.exist?(@backup_dir)

    @applier.apply!

    assert Dir.exist?(@backup_dir)
  end

  test "should generate valid XML with new configs" do
    preview = @applier.preview_changes
    xml_content = preview[:xml_preview]

    # Should be valid XML
    parsed = Nokogiri::XML(xml_content)

    assert_empty parsed.errors, "Generated XML should be valid"

    # Should contain new config
    backups_config = parsed.xpath("//Config[@Name='Backups']").first

    refute_nil backups_config
    assert_equal "/backups", backups_config["Target"]
    assert_equal "Backup storage", backups_config["Description"]
  end

  test "should convert single-word community categories to UnRAID format with trailing colon" do
    community_category = "Downloaders"
    applier = TemplateChangesApplier.new(@comparison)

    result = applier.send(:convert_category_to_unraid_format, community_category)

    assert_equal "Downloaders:", result
  end

  test "should convert multi-part community categories to UnRAID format without trailing colon" do
    community_category = "Tools-Utilities"
    applier = TemplateChangesApplier.new(@comparison)

    result = applier.send(:convert_category_to_unraid_format, community_category)

    assert_equal "Tools:Utilities", result
  end

  test "should convert complex community categories to UnRAID format" do
    community_category = "MediaApp-Video-Other"
    applier = TemplateChangesApplier.new(@comparison)

    result = applier.send(:convert_category_to_unraid_format, community_category)

    assert_equal "MediaApp:Video:Other", result
  end

  test "should handle empty and nil categories in conversion" do
    applier = TemplateChangesApplier.new(@comparison)

    assert_nil applier.send(:convert_category_to_unraid_format, nil)
    assert_equal "", applier.send(:convert_category_to_unraid_format, "")
    assert_equal "  ", applier.send(:convert_category_to_unraid_format, "  ")
  end

  test "should apply category changes with proper UnRAID format conversion" do
    xml_with_category = @local_xml.gsub(
      "<Network>bridge</Network>",
      "<Network>bridge</Network>\n  <Category>Backup:</Category>",
    )
    File.write(@template_file, xml_with_category)
    @local_template.xml_content = xml_with_category
    @local_template.category = "Backup:"

    @comparison.update!(
      differences: {
        "category" => {
          "type" => "basic_field",
          "local" => "Backup:",
          "community" => "Downloaders",
          "field_name" => "Category",
        },
      },
      user_choices: {
        "category" => "community",
      },
    )

    @applier.apply!

    updated_content = File.read(@template_file)

    assert_includes updated_content, "<Category>Downloaders:</Category>"
  end

  test "should use manual edits when available for basic fields" do
    @comparison.update!(
      status: "reviewed",
      user_choices: {
        "network" => "community",
        "webui" => "community",
      },
      manual_edits: {
        "network" => "custom_network",
        "webui" => "http://[IP]:[PORT:8300]/custom",
      },
    )

    applier = TemplateChangesApplier.new(@comparison)

    assert applier.apply!

    @local_template.reload

    assert_equal "custom_network", @local_template.network
    assert_equal "http://[IP]:[PORT:8300]/custom", @local_template.webui

    # Check that local template file was updated with manual edits
    updated_content = File.read(@template_file)

    assert_includes updated_content, "<Network>custom_network</Network>"
    assert_includes updated_content, "<WebUI>http://[IP]:[PORT:8300]/custom</WebUI>"
  end

  test "should use manual edits for config field changes" do
    @comparison.update!(
      differences: {
        "config_WebUI" => {
          "type" => "config",
          "config_name" => "WebUI",
          "field_differences" => {
            "description" => {
              "local" => "WebUI port",
              "community" => "Web interface port",
            },
          },
        },
      },
      user_choices: {
        "config_WebUI_description" => "community",
      },
      manual_edits: {
        "config_WebUI_description" => "Custom web interface port",
      },
    )

    applier = TemplateChangesApplier.new(@comparison)
    updated_xml = applier.send(:generate_updated_xml)

    assert_includes updated_xml, 'Description="Custom web interface port"'
  end
end
