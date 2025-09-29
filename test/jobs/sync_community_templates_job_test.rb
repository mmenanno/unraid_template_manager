# frozen_string_literal: true

require "test_helper"

class SyncCommunityTemplatesJobTest < ActiveJob::TestCase
  def setup
    @local_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "bridge",
      category: "Backup:",
      webui: "http://[IP]:[PORT:8200]",
      description: "Duplicati backup client",
      xml_content: "<Container><Name>duplicati</Name></Container>",
      source: "local",
    )

    @community_response = {
      "Name" => "duplicati",
      "Repository" => "lscr.io/linuxserver/duplicati:latest",
      "Network" => "host",
      "CategoryList" => ["Backup:"],
      "Icon" => "https://example.com/icon.png",
      "WebUI" => "http://[IP]:[PORT:8200]/web",
      "Overview" => "Duplicati backup client with encryption",
      "TemplateURL" => "https://example.com/template.xml",
    }
  end

  test "should sync community templates" do
    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .with("lscr.io/linuxserver/duplicati:latest")
      .returns(@community_response)

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns("<Container><Name>duplicati</Name><Network>host</Network><WebUI>http://[IP]:[PORT:8200]/web</WebUI></Container>")

    Faraday.stubs(:get)
      .with("https://example.com/template.xml")
      .returns(mock_response)
    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 1, result[:created]
    assert_equal 0, result[:updated]
    assert_equal 0, result[:errors]
  end

  test "should create community template with correct attributes" do
    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .with("lscr.io/linuxserver/duplicati:latest")
      .returns(@community_response)

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns("<Container><Name>duplicati</Name><Network>host</Network><WebUI>http://[IP]:[PORT:8200]/web</WebUI></Container>")

    Faraday.stubs(:get)
      .with("https://example.com/template.xml")
      .returns(mock_response)

    SyncCommunityTemplatesJob.perform_now

    community_template = Template.community.first

    assert_equal "duplicati", community_template.name
    assert_equal "host", community_template.network
    assert_equal "https://example.com/icon.png", community_template.banner
    assert_equal "http://[IP]:[PORT:8200]/web", community_template.webui
  end

  test "should create template comparison when syncing community templates" do
    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .with("lscr.io/linuxserver/duplicati:latest")
      .returns(@community_response)

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns("<Container><Name>duplicati</Name><Network>host</Network><WebUI>http://[IP]:[PORT:8200]/web</WebUI></Container>")

    Faraday.stubs(:get)
      .with("https://example.com/template.xml")
      .returns(mock_response)

    SyncCommunityTemplatesJob.perform_now

    assert_equal 1, TemplateComparison.count
  end

  test "should update existing community templates" do
    community_template = Template.create!(
      name: "duplicati",
      repository: "lscr.io/linuxserver/duplicati:latest",
      network: "bridge",
      category: "Backup:",
      xml_content: "<Container><Name>duplicati</Name></Container>",
      source: "community",
    )

    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .returns(@community_response)

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns("<Container><Name>duplicati</Name><Network>host</Network><WebUI>http://[IP]:[PORT:8200]/web</WebUI></Container>")

    Faraday.stubs(:get)
      .with("https://example.com/template.xml")
      .returns(mock_response)

    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 0, result[:created]
    assert_equal 1, result[:updated]

    community_template.reload

    assert_equal "host", community_template.network
  end

  test "should handle API errors gracefully" do
    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .raises(StandardError, "API error")

    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 0, result[:created]
    assert_equal 0, result[:updated]
    assert_equal 1, result[:errors]
  end

  test "should skip templates marked as not in community" do
    @local_template.update!(not_in_community: true)

    # Should not call the client for templates marked as not in community
    CommunityApplicationsClient.any_instance
      .expects(:find_template_by_repository)
      .never

    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 0, result[:created]
    assert_equal 0, result[:updated]
    assert_equal 0, result[:errors]
  end

  test "should process templates not marked as not in community" do
    @local_template.update!(not_in_community: false)

    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .with("lscr.io/linuxserver/duplicati:latest")
      .returns(@community_response)

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns("<Container><Name>duplicati</Name><Network>host</Network></Container>")

    Faraday.stubs(:get)
      .with("https://example.com/template.xml")
      .returns(mock_response)

    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 1, result[:created]
    assert_equal 0, result[:updated]
    assert_equal 0, result[:errors]
  end
end
