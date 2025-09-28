# frozen_string_literal: true

require "test_helper"

class CommunityApplicationsClientTest < ActiveSupport::TestCase
  def setup
    @client = CommunityApplicationsClient.new
    @sample_feed = {
      "applications" => [
        {
          "Name" => "duplicati",
          "Repository" => "lscr.io/linuxserver/duplicati:latest",
          "Network" => "bridge",
          "Category" => "Backup:",
          "Icon" => "https://example.com/duplicati.png",
          "WebUI" => "http://[IP]:[PORT:8200]",
          "Overview" => "Duplicati is a backup client",
          "Date" => "1640995200",
          "Support" => "https://forums.unraid.net/topic/57181",
          "Project" => "https://www.duplicati.com/",
        },
        {
          "Name" => "plex",
          "Repository" => "lscr.io/linuxserver/plex:latest",
          "Network" => "host",
          "Category" => "MediaServer:Video",
          "Icon" => "https://example.com/plex.png",
          "WebUI" => "http://[IP]:[PORT:32400]/web",
          "Overview" => "Plex Media Server",
          "Date" => "1640995300",
        },
      ],
    }.to_json
  end

  test "should fetch and parse feed successfully" do
    stub_successful_feed_request

    feed_data = @client.fetch_feed

    assert_equal 2, feed_data["applications"].size
    assert_equal "duplicati", feed_data["applications"].first["Name"]
  end

  test "should raise FeedUnavailableError on network error" do
    stub_feed_request_failure

    assert_raises(CommunityApplicationsClient::FeedUnavailableError) do
      @client.fetch_feed
    end
  end

  test "should raise ParseError on invalid JSON" do
    stub_request(:get, CommunityApplicationsClient::FEED_URL)
      .to_return(status: 200, body: "invalid json")

    assert_raises(CommunityApplicationsClient::ParseError) do
      @client.fetch_feed
    end
  end

  test "should find template by repository" do
    stub_successful_feed_request

    template_data = @client.find_template_by_repository("lscr.io/linuxserver/duplicati:latest")

    refute_nil template_data
    assert_equal "duplicati", template_data["Name"]
  end

  test "should find template by normalized repository" do
    stub_successful_feed_request

    # Test finding with different repository formats (matching the sample data)
    template_data = @client.find_template_by_repository("linuxserver/duplicati:latest")

    refute_nil template_data
    assert_equal "duplicati", template_data["Name"]
  end

  test "should return nil when template not found" do
    stub_successful_feed_request

    template_data = @client.find_template_by_repository("nonexistent/app")

    assert_nil template_data
  end

  test "should search templates by query" do
    stub_successful_feed_request

    results = @client.search_templates("backup")

    assert_equal 1, results.size
    assert_equal "duplicati", results.first["Name"]
  end

  test "should search templates by name" do
    stub_successful_feed_request

    results = @client.search_templates("plex")

    assert_equal 1, results.size
    assert_equal "plex", results.first["Name"]
  end

  test "should return empty array when no search matches" do
    stub_successful_feed_request

    results = @client.search_templates("nonexistent")

    assert_empty results
  end

  test "should convert app data to template" do
    app_data = {
      "Name" => "duplicati",
      "Repository" => "lscr.io/linuxserver/duplicati:latest",
      "Network" => "bridge",
      "Category" => "Backup:",
      "Icon" => "https://example.com/duplicati.png",
      "WebUI" => "http://[IP]:[PORT:8200]",
      "Overview" => "Duplicati is a backup client",
      "Date" => "1640995200",
    }

    template = @client.convert_to_template(app_data)

    assert_equal "duplicati", template.name
    assert_equal "lscr.io/linuxserver/duplicati:latest", template.repository
    assert_equal "community", template.source
    assert_equal "bridge", template.network
    assert_equal "Backup:", template.category
    refute_nil template.xml_content
    assert_includes template.xml_content, "<Name>duplicati</Name>"
  end

  test "should handle nil app data" do
    template = @client.convert_to_template(nil)

    assert_nil template
  end

  test "should build valid XML from app data" do
    app_data = {
      "Name" => "test-app",
      "Repository" => "test/app:latest",
      "Network" => "bridge",
      "Overview" => "Test application",
    }

    template = @client.convert_to_template(app_data)
    parsed_xml = Nokogiri::XML(template.xml_content)

    assert_equal "test-app", parsed_xml.at("Name").text
    assert_equal "test/app:latest", parsed_xml.at("Repository").text
    assert_equal "bridge", parsed_xml.at("Network").text
    assert_equal "Test application", parsed_xml.at("Overview").text
  end

  private

  def stub_successful_feed_request
    stub_request(:get, CommunityApplicationsClient::FEED_URL)
      .to_return(status: 200, body: @sample_feed, headers: { "Content-Type" => "application/json" })
  end

  def stub_feed_request_failure
    stub_request(:get, CommunityApplicationsClient::FEED_URL)
      .to_return(status: 500, body: "Internal Server Error")
  end
end
