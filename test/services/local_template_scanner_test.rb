# frozen_string_literal: true

require "test_helper"

class LocalTemplateScannerTest < ActiveSupport::TestCase
  def setup
    @temp_dir = Dir.mktmpdir("unraid_templates")
    @scanner = LocalTemplateScanner.new(template_directory: @temp_dir)
    @sample_xml = Rails.root.join("test/fixtures/sample_template.xml").read
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  test "should scan templates from directory" do
    create_template_file("duplicati.xml", @sample_xml)
    create_template_file("plex.xml", modified_xml_for_plex)

    templates = @scanner.scan_templates

    assert_equal 2, templates.size
    duplicati_template = templates.find { |t| t[:name] == "duplicati" }

    refute_nil duplicati_template
    assert_equal "lscr.io/linuxserver/duplicati:latest", duplicati_template[:repository]
    assert_equal "local", duplicati_template[:source]
  end

  test "should raise error if directory does not exist" do
    scanner = LocalTemplateScanner.new(template_directory: "/nonexistent/directory")

    assert_raises(LocalTemplateScanner::DirectoryNotFoundError) do
      scanner.scan_templates
    end
  end

  test "should handle invalid XML files gracefully" do
    create_template_file("valid.xml", @sample_xml)
    create_template_file("invalid.xml", "invalid xml content")

    templates = @scanner.scan_templates

    # Should return only the valid template
    assert_equal 1, templates.size
    assert_equal "duplicati", templates.first[:name]
  end

  test "should find template by name" do
    create_template_file("duplicati.xml", @sample_xml)

    template = @scanner.find_template_by_name("duplicati")

    refute_nil template
    assert_equal "duplicati", template[:name]
  end

  test "should return nil for nonexistent template" do
    template = @scanner.find_template_by_name("nonexistent")

    assert_nil template
  end

  test "should sync local templates to database" do
    create_template_file("duplicati.xml", @sample_xml)
    create_template_file("plex.xml", modified_xml_for_plex)

    assert_difference "Template.count", 2 do
      result = @scanner.sync_local_templates!

      assert_equal 2, result[:created]
    end

    duplicati = Template.find_by(name: "duplicati")

    refute_nil duplicati
    assert_equal "local", duplicati.source
    assert_equal "active", duplicati.status
    assert_predicate duplicati.template_configs, :any?
  end

  test "should update existing templates when XML changes" do
    create_template_file("duplicati.xml", @sample_xml)

    # First sync
    @scanner.sync_local_templates!
    original_template = Template.find_by(name: "duplicati")
    original_updated_at = original_template.last_updated_at

    # Modify the template file
    modified_xml = @sample_xml.gsub("<Name>duplicati</Name>", "<Name>duplicati-modified</Name>")
    create_template_file("duplicati.xml", modified_xml)

    # Second sync - should update existing template
    assert_no_difference "Template.count" do
      @scanner.sync_local_templates!
    end

    updated_template = Template.find_by(repository: "lscr.io/linuxserver/duplicati:latest")

    assert_equal "duplicati-modified", updated_template.name
    assert_operator updated_template.last_updated_at, :>, original_updated_at
  end

  test "should mark missing templates as inactive" do
    # Create and sync a template
    create_template_file("duplicati.xml", @sample_xml)
    @scanner.sync_local_templates!

    template = Template.find_by(name: "duplicati")

    assert_equal "active", template.status

    # Remove the file and sync again
    File.delete(File.join(@temp_dir, "duplicati.xml"))
    @scanner.sync_local_templates!

    template.reload

    assert_equal "inactive", template.status
  end

  test "should handle binary files gracefully" do
    # Create a binary file with .xml extension
    binary_file = File.join(@temp_dir, "binary.xml")
    File.write(binary_file, "\x00\x01\x02\x03", mode: "wb")

    # Should not crash and return empty array
    templates = @scanner.scan_templates

    assert_empty templates
  end

  test "should extract template data correctly" do
    create_template_file("duplicati.xml", @sample_xml)

    templates = @scanner.scan_templates
    template = templates.first

    assert_equal "duplicati", template[:name]
    assert_equal "lscr.io/linuxserver/duplicati:latest", template[:repository]
    assert_equal "bridge", template[:network]
    assert_equal "Backup:", template[:category]
    assert_includes template[:xml_content], "<Container version=\"2\">"
    assert_equal File.join(@temp_dir, "duplicati.xml"), template[:local_path]
    assert_kind_of Time, template[:last_updated_at]
  end

  private

  def create_template_file(filename, content)
    File.write(File.join(@temp_dir, filename), content)
  end

  def modified_xml_for_plex
    @sample_xml.gsub("duplicati", "plex")
      .gsub("lscr.io/linuxserver/duplicati:latest", "lscr.io/linuxserver/plex:latest")
      .gsub("Backup:", "MediaServer:Video")
  end
end
