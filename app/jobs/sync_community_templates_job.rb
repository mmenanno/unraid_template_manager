# frozen_string_literal: true

class SyncCommunityTemplatesJob < ApplicationJob
  queue_as :default

  def perform
    job_run = SyncJobRun.create_for_job("community_sync")

    begin
      Rails.logger.info("Starting community template sync")

      client = CommunityApplicationsClient.new
      results = { created: 0, updated: 0, errors: 0, error_details: [] }

      # Get all local templates that need community counterparts (excluding those marked as not in community)
      local_templates = Template.local.active.in_community

      local_templates.find_each do |local_template|
        # Use manual repository mapping if available, otherwise use template repository
        search_repository = local_template.community_repository.presence || local_template.repository

        # Find matching community template
        community_data = client.find_template_by_repository(search_repository)

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
          Rails.logger.debug { "No community template found for: #{search_repository} (local: #{local_template.repository})" }
          results[:error_details] << {
            template: local_template.name,
            repository: local_template.repository,
            search_repository: search_repository,
            error: "No matching Community Applications template found",
          }
        end
      rescue => e
        Rails.logger.error("Failed to sync community template for #{local_template.repository}: #{e.message}")
        results[:errors] += 1
        results[:error_details] << {
          template: local_template.name,
          repository: local_template.repository,
          search_repository: search_repository,
          error: e.message,
        }
      end

      Rails.logger.info("Community template sync completed: #{results[:created]} created, #{results[:updated]} updated, #{results[:errors]} errors")

      job_run.complete!(results)
      results
    rescue => e
      Rails.logger.error("Community template sync failed: #{e.message}")
      job_run.fail!(e.message)
      raise
    end
  end

  private

  def sync_community_template(community_data)
    xml_content = fetch_template_xml(community_data["TemplateURL"])

    # If we can't fetch XML content from TemplateURL, try to build it from the feed data
    if xml_content.blank?
      Rails.logger.debug { "TemplateURL is empty or unavailable for #{community_data["Name"]}, building XML from feed data" }
      xml_content = build_xml_from_app_data(community_data)
    end

    # If we still can't get XML content, we can't create a proper template
    if xml_content.blank?
      raise "Unable to generate template XML for #{community_data["Name"]} - both TemplateURL and feed data are insufficient"
    end

    template_data = {
      name: community_data["Name"],
      repository: community_data["Repository"],
      network: community_data["Network"],
      category: community_data["CategoryList"]&.first,
      banner: community_data["Icon"],
      webui: extract_webui_from_xml(xml_content),
      description: community_data["Overview"],
      xml_content: xml_content,
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

  def fetch_template_xml(template_url)
    return if template_url.blank?

    Rails.logger.debug { "Fetching template XML from: #{template_url}" }

    response = Faraday.get(template_url)

    if response.success?
      xml_content = response.body
      if xml_content.blank?
        Rails.logger.warn("Template XML from #{template_url} is empty")
        return
      end
      xml_content
    else
      Rails.logger.warn("Failed to fetch template XML from #{template_url}: #{response.status}")
      nil
    end
  rescue => e
    Rails.logger.error("Error fetching template XML from #{template_url}: #{e.message}")
    nil
  end

  def extract_webui_from_xml(xml_content)
    return if xml_content.blank?

    doc = Nokogiri::XML(xml_content)
    doc.at("WebUI")&.text&.strip
  rescue => e
    Rails.logger.debug { "Could not extract WebUI from XML: #{e.message}" }
    nil
  end

  def build_xml_from_app_data(app_data)
    xml = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.Container(version: "2") do
        xml.Name(app_data["Name"]) if app_data["Name"]
        xml.Repository(app_data["Repository"]) if app_data["Repository"]
        xml.Registry(app_data["Registry"]) if app_data["Registry"]
        xml.Network(app_data["Network"]) if app_data["Network"]
        xml.Privileged(app_data["Privileged"]) if app_data["Privileged"]
        xml.Support(app_data["Support"]) if app_data["Support"]
        xml.Project(app_data["Project"]) if app_data["Project"]
        xml.Overview(app_data["Overview"]) if app_data["Overview"]
        xml.Category(app_data["CategoryList"]&.first) if app_data["CategoryList"]&.first
        xml.WebUI(app_data["WebUI"]) if app_data["WebUI"]
        xml.Icon(app_data["Icon"]) if app_data["Icon"]
        xml.TemplateURL(app_data["TemplateURL"]) if app_data["TemplateURL"]
        xml.Shell(app_data["Shell"]) if app_data["Shell"]
        xml.ExtraParams(app_data["ExtraParams"]) if app_data["ExtraParams"]

        # Add config elements if present
        app_data["Config"]&.each do |config|
          next unless config.is_a?(Hash)

          # Handle the Community Applications feed structure where configs have @attributes
          if config["@attributes"]
            attrs = config["@attributes"]
            content = config["value"] || ""
            xml.Config(content, attrs)
          else
            # Handle direct attribute structure (fallback)
            attrs = {}
            config.each { |k, v| attrs[k] = v unless k == "content" }
            xml.Config(config["content"] || "", attrs)
          end
        end
      end
    end

    xml.to_xml
  end
end
