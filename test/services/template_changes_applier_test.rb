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
end
