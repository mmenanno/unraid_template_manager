# frozen_string_literal: true

class SyncCommunityTemplatesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("Starting community template sync")

    client = CommunityApplicationsClient.new
    results = { created: 0, updated: 0, errors: 0 }

    # Get all local templates that need community counterparts
    local_templates = Template.local.active

    local_templates.find_each do |local_template|
      # Find matching community template
      community_data = client.find_template_by_repository(local_template.repository)

      if community_data
        community_template = sync_community_template(community_data)

        if community_template.previously_new_record?
          results[:created] += 1
        else
          results[:updated] += 1
        end

        # Create or update comparison
        local_template.find_or_create_comparison_with(community_template)
      else
        Rails.logger.debug { "No community template found for: #{local_template.repository}" }
      end
    rescue => e
      Rails.logger.error("Failed to sync community template for #{local_template.repository}: #{e.message}")
      results[:errors] += 1
    end

    Rails.logger.info("Community template sync completed: #{results[:created]} created, #{results[:updated]} updated, #{results[:errors]} errors")

    results
  rescue => e
    Rails.logger.error("Community template sync failed: #{e.message}")
    raise
  end

  private

  def sync_community_template(community_data)
    template_data = {
      name: community_data["Name"],
      repository: community_data["Repository"],
      network: community_data["Network"],
      category: community_data["Category"],
      banner: community_data["Icon"],
      webui: community_data["WebUI"],
      description: community_data["Overview"],
      xml_content: community_data["template"],
      source: "community",
      last_updated_at: Time.current,
    }

    template = Template.find_or_initialize_by(
      repository: community_data["Repository"],
      source: "community",
    )

    template.assign_attributes(template_data)
    template.save!
    template.sync_configs_from_xml!

    template
  end
end
