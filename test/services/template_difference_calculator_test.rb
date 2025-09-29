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

  test "should ignore HTML tag differences in description field" do
    # Create templates with same content but different HTML formatting
    local_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>mongodb</Name>
        <Repository>mongo</Repository>
        <Overview>MongoDBMongoDB (from "humongous") is a database</Overview>
      </Container>
    XML

    community_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>mongodb</Name>
        <Repository>mongo</Repository>
        <Overview>[h3]MongoDB[/h3]MongoDB (from "humongous") is a database</Overview>
      </Container>
    XML

    local_template = Template.create!(
      name: "mongodb",
      repository: "mongo-local",
      description: "MongoDBMongoDB (from \"humongous\") is a database",
      xml_content: local_xml,
      source: "local",
    )

    community_template = Template.create!(
      name: "mongodb",
      repository: "mongo-community",
      description: "[h3]MongoDB[/h3]MongoDB (from \"humongous\") is a database",
      xml_content: community_xml,
      source: "community",
    )

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    # Should not detect a difference since the content is the same after stripping tags
    refute_includes differences, "description"
  end

  test "should still detect real content differences in description field with HTML tags" do
    # Create templates with different content even after stripping HTML
    local_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>mongodb</Name>
        <Repository>mongo</Repository>
        <Overview>[h3]MongoDB[/h3]MongoDB is a database</Overview>
      </Container>
    XML

    community_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>mongodb</Name>
        <Repository>mongo</Repository>
        <Overview>[h3]MongoDB[/h3]MongoDB is a NoSQL database</Overview>
      </Container>
    XML

    local_template = Template.create!(
      name: "mongodb",
      repository: "mongo-local",
      description: "[h3]MongoDB[/h3]MongoDB is a database",
      xml_content: local_xml,
      source: "local",
    )

    community_template = Template.create!(
      name: "mongodb",
      repository: "mongo-community",
      description: "[h3]MongoDB[/h3]MongoDB is a NoSQL database",
      xml_content: community_xml,
      source: "community",
    )

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    # Should detect a difference since the content is different after stripping tags
    assert_includes differences, "description"
    assert_equal "MongoDBMongoDB is a database", differences["description"]["local"]
    assert_equal "MongoDBMongoDB is a NoSQL database", differences["description"]["community"]
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
    # For truly identical templates, we need to create a local template that
    # has actual values set to match what the calculator expects for community templates
    local_xml_with_values = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>duplicati</Name>
        <Repository>lscr.io/linuxserver/duplicati:latest</Repository>
        <Network>bridge</Network>
        <Category>Backup:</Category>
        <WebUI>http://[IP]:[PORT:8200]</WebUI>
        <Overview>Duplicati is a backup client</Overview>
        <Config Name="WebUI" Target="8200" Default="8200" Mode="tcp" Description="WebUI port" Type="Port" Required="true" Display="always">8200</Config>
        <Config Name="Appdata" Target="/config" Default="/mnt/user/appdata/duplicati" Mode="rw" Description="Config files" Type="Path" Required="true" Display="always">/mnt/user/appdata/duplicati</Config>
      </Container>
    XML

    local_template_with_values = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest-local-with-values",
      network: "bridge",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]",
      description: "Duplicati is a backup client",
      xml_content: local_xml_with_values,
      source: "local",
    )

    community_template_identical = Template.create!(
      name: @local_template.name,
      repository: "lscr.io/linuxserver/duplicati:latest-identical",
      network: @local_template.network,
      category: @local_template.category,
      webui: @local_template.webui,
      description: @local_template.description,
      xml_content: local_xml_with_values,
      source: "community",
    )

    calculator = TemplateDifferenceCalculator.new(local_template_with_values, community_template_identical)
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

  test "should normalize single-word categories with trailing colons" do
    local_template = @local_template.dup
    local_template.category = "Downloaders:"

    community_template = @community_template.dup
    community_template.category = "Downloaders"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should normalize multi-part categories with colon-to-hyphen conversion" do
    local_template = @local_template.dup
    local_template.category = "MediaApp:Other"

    community_template = @community_template.dup
    community_template.category = "MediaApp-Other"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should normalize categories with trailing content" do
    local_template = @local_template.dup
    local_template.category = "Tools:Utilities spotlight:"

    community_template = @community_template.dup
    community_template.category = "Tools-Utilities"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should normalize complex multi-category strings" do
    local_template = @local_template.dup
    local_template.category = "Downloaders: MediaApp:Video Tools:Utilities"

    community_template = @community_template.dup
    community_template.category = "Downloaders"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should detect legitimate category differences" do
    local_template = @local_template.dup
    local_template.category = "Tools:Utilities"

    community_template = @community_template.dup
    community_template.category = "MediaApp-Video"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    assert_includes differences, "category"
    assert_equal "Tools-Utilities", differences["category"]["local"]
    assert_equal "MediaApp-Video", differences["category"]["community"]
  end

  test "should handle empty and nil categories" do
    local_template = @local_template.dup
    local_template.category = ""

    community_template = @community_template.dup
    community_template.category = nil

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should skip normalization for exact category matches" do
    local_template = @local_template.dup
    local_template.category = "Downloaders:"

    community_template = @community_template.dup
    community_template.category = "Downloaders:"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
  end

  test "should skip normalization for any exact field matches" do
    local_template = @local_template.dup
    local_template.category = "Tools:Utilities"
    local_template.webui = "http://[IP]:[PORT:8200]"
    local_template.description = "Same description"

    community_template = @community_template.dup
    community_template.category = "Tools:Utilities"
    community_template.webui = "http://[IP]:[PORT:8300]"
    community_template.description = "Same description"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"
    refute_includes differences, "description"

    assert_includes differences, "webui"
  end

  test "should preserve original values when no normalization is needed" do
    local_template = @local_template.dup
    local_template.category = "Custom:Category:With:Colons"

    community_template = @community_template.dup
    community_template.category = "Custom:Category:With:Colons"

    calculator = TemplateDifferenceCalculator.new(local_template, community_template)
    differences = calculator.calculate

    refute_includes differences, "category"

    assert_equal "Custom:Category:With:Colons", local_template.category
    assert_equal "Custom:Category:With:Colons", community_template.category
  end
end
