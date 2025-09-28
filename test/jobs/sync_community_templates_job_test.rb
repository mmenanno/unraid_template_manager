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
      "Category" => "Backup:",
      "Icon" => "https://example.com/icon.png",
      "WebUI" => "http://[IP]:[PORT:8200]/web",
      "Overview" => "Duplicati backup client with encryption",
      "template" => "<Container><Name>duplicati</Name><Network>host</Network></Container>",
    }
  end

  test "should sync community templates" do
    CommunityApplicationsClient.any_instance
      .stubs(:find_template_by_repository)
      .with("lscr.io/linuxserver/duplicati:latest")
      .returns(@community_response)

    result = SyncCommunityTemplatesJob.perform_now

    assert_equal 1, result[:created]
    assert_equal 0, result[:updated]
    assert_equal 0, result[:errors]

    community_template = Template.community.first

    assert_equal "duplicati", community_template.name
    assert_equal "host", community_template.network
    assert_equal "https://example.com/icon.png", community_template.banner

    # Should create comparison
    assert_equal 1, TemplateComparison.count
  end

  test "should update existing community templates" do
    # Create existing community template
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
end
