# frozen_string_literal: true

class UpdateTemplateComparisonsJob < ApplicationJob
  queue_as :default

  def perform(template_id = nil)
    Rails.logger.info("Starting template comparison updates")

    if template_id
      # Update comparisons for a specific template
      template = Template.find(template_id)
      update_comparisons_for_template(template)
    else
      # Update all comparisons
      results = { updated: 0, created: 0, errors: 0 }

      Template.local.active.find_each do |local_template|
        community_template = local_template.matching_community_template
        next unless community_template

        comparison = local_template.find_or_create_comparison_with(community_template)

        if comparison.previously_new_record?
          results[:created] += 1
        else
          results[:updated] += 1
        end
      rescue => e
        Rails.logger.error("Failed to update comparison for #{local_template.name}: #{e.message}")
        results[:errors] += 1
      end

      Rails.logger.info("Template comparison updates completed: #{results[:created]} created, #{results[:updated]} updated, #{results[:errors]} errors")
      results
    end
  rescue => e
    Rails.logger.error("Template comparison update failed: #{e.message}")
    raise
  end

  private

  def update_comparisons_for_template(template)
    return unless template.local?

    community_template = template.matching_community_template
    return unless community_template

    template.find_or_create_comparison_with(community_template)
    Rails.logger.info("Updated comparison for template: #{template.name}")
  end
end
