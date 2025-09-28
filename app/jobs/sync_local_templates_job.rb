# frozen_string_literal: true

class SyncLocalTemplatesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("Starting local template sync")

    scanner = LocalTemplateScanner.new
    result = scanner.sync_local_templates!

    Rails.logger.info("Local template sync completed: #{result[:created]} created, #{result[:updated]} updated, #{result[:removed]} removed")

    # After syncing local templates, sync community templates
    SyncCommunityTemplatesJob.perform_later

    result
  rescue => e
    Rails.logger.error("Local template sync failed: #{e.message}")
    raise
  end
end
