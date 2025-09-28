# frozen_string_literal: true

require "test_helper"

class TemplateDifferenceCalculatorTest < ActiveSupport::TestCase
  def setup
    @local_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>duplicati</Name>
        <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
        <Network>bridge</Network>
        <Category>Backup:</Category>
        <WebUI>http://[IP]:[PORT:8200]</WebUI>
        <Overview>Duplicati is a backup client</Overview>
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
        <Category>Backup:</Category>
        <WebUI>http://[IP]:[PORT:8200]/web</WebUI>
        <Overview>Duplicati is a backup client that stores encrypted backups</Overview>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="Web interface port" Type="Port" Required="true" Display="always"/>
        <Config Name="Appdata" Target="/config" Default="/mnt/user/appdata/duplicati" Mode="rw" Description="Config files" Type="Path" Required="true" Display="always"/>
        <Config Name="Backups" Target="/backups" Default="/mnt/user/backups" Mode="rw" Description="Backup storage" Type="Path" Required="false" Display="always"/>
      </Container>
    XML

    @local_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest-local",
      network: "bridge",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]",
      description: "Duplicati is a backup client",
      xml_content: @local_xml,
      source: "local",
    )

    @community_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest-community",
      network: "host",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]/web",
      description: "Duplicati is a backup client that stores encrypted backups",
      xml_content: @community_xml,
      source: "community",
    )

    @calculator = TemplateDifferenceCalculator.new(@local_template, @community_template)
  end

  test "should return empty hash when templates are nil" do
    calculator = TemplateDifferenceCalculator.new(nil, nil)
    differences = calculator.calculate

    assert_empty(differences)
  end

  test "should detect network field differences" do
    differences = @calculator.calculate

    assert_includes differences, "network"
    assert_equal "bridge", differences["network"]["local"]
    assert_equal "host", differences["network"]["community"]
    assert_equal "basic_field", differences["network"]["type"]
  end

  test "should detect webui field differences" do
    differences = @calculator.calculate

    assert_includes differences, "webui"
    assert_equal "http://[IP]:[PORT:8200]", differences["webui"]["local"]
    assert_equal "http://[IP]:[PORT:8200]/web", differences["webui"]["community"]
  end

  test "should detect description field differences" do
    differences = @calculator.calculate

    assert_includes differences, "description"
    assert_equal "Duplicati is a backup client", differences["description"]["local"]
    assert_equal "Duplicati is a backup client that stores encrypted backups", differences["description"]["community"]
  end

  test "should detect config differences" do
    differences = @calculator.calculate

    # WebUI config should have description difference
    assert_includes differences, "config_WebUI"
    config_diff = differences["config_WebUI"]

    assert_equal "config", config_diff["type"]
    assert_equal "WebUI", config_diff["config_name"]
    assert_includes config_diff["field_differences"], "description"
    assert_equal "WebUI port", config_diff["field_differences"]["description"]["local"]
    assert_equal "Web interface port", config_diff["field_differences"]["description"]["community"]
  end

  test "should detect new configs" do
    differences = @calculator.calculate

    # Backups config only exists in community template
    assert_includes differences, "new_config_Backups"
    new_config = differences["new_config_Backups"]

    assert_equal "new_config", new_config["type"]
    assert_equal "Backups", new_config["config_name"]
    assert_equal "/backups", new_config["community"][:target]
    assert_equal "Backup storage", new_config["community"][:description]
  end

  test "should detect removed configs" do
    # Reverse the templates to test removal
    calculator = TemplateDifferenceCalculator.new(@community_template, @local_template)
    differences = calculator.calculate

    # From this perspective, Backups config was removed
    assert_includes differences, "removed_config_Backups"
    removed_config = differences["removed_config_Backups"]

    assert_equal "removed_config", removed_config["type"]
    assert_equal "Backups", removed_config["config_name"]
  end

  test "should handle identical templates" do
    identical_template = Template.create!(
      name: @local_template.name,
      repository: "lscr.io/linuxserver/duplicati:latest-identical",
      network: @local_template.network,
      category: @local_template.category,
      webui: @local_template.webui,
      description: @local_template.description,
      xml_content: @local_template.xml_content,
      source: "community",
    )

    calculator = TemplateDifferenceCalculator.new(@local_template, identical_template)
    differences = calculator.calculate

    assert_empty differences
  end

  test "should normalize whitespace and empty values" do
    local_xml_with_whitespace = @local_xml.gsub("<Network>bridge</Network>", "<Network>  bridge  </Network>")
    community_xml_with_empty = @community_xml.gsub("<Network>host</Network>", "<Network></Network>")

    local_template = @local_template.dup
    local_template.xml_content = local_xml_with_whitespace

    community_template = @community_template.dup
    community_template.xml_content = community_xml_with_empty
    community_template.network = ""

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    assert_includes differences, "network"
    assert_equal "bridge", differences["network"]["local"] # Normalized
    assert_nil differences["network"]["community"] # Empty string normalized to nil
  end

  test "should handle malformed XML gracefully" do
    local_template = @local_template.dup
    local_template.xml_content = "invalid xml content"

    calculator = TemplateDifferenceCalculator.new(local_template, @community_template)

    # Should not crash, but may have limited comparison
    assert_nothing_raised do
      differences = calculator.calculate

      assert_kind_of Hash, differences
    end
  end
end
