# frozen_string_literal: true

require "test_helper"

class SyncLocalTemplatesJobTest < ActiveJob::TestCase
  def setup
    @temp_dir = Dir.mktmpdir("unraid_templates")
    Rails.application.config.stubs(:template_directory).returns(@temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  test "should sync local templates" do
    # Create a test template file
    template_xml = <<~XML
      <?xml version="1.0"?>
      <Container version="2">
        <Name>test-app</Name>
        <Repository>lscr.io/linuxserver/test-app:latest</Repository>
        <Network>bridge</Network>
        <Category>Tools:</Category>
        <WebUI>http://[IP]:[PORT:8080]</WebUI>
        <Overview>Test application</Overview>
      </Container>
    XML

    File.write(File.join(@temp_dir, "test-app.xml"), template_xml)

    assert_enqueued_with(job: SyncCommunityTemplatesJob) do
      SyncLocalTemplatesJob.perform_now
    end

    assert_equal 1, Template.local.count
    template = Template.local.first

    assert_equal "test-app", template.name
    assert_equal "lscr.io/linuxserver/test-app:latest", template.repository
  end

  test "should handle job failures gracefully" do
    # Stub the scanner to raise an error
    LocalTemplateScanner.any_instance.stubs(:sync_local_templates!).raises(StandardError, "Test error")

    assert_raises(StandardError) do
      SyncLocalTemplatesJob.perform_now
    end
  end
end
