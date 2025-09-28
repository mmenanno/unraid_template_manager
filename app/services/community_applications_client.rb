# frozen_string_literal: true

class CommunityApplicationsClient
  FEED_URL = "https://raw.githubusercontent.com/Squidly271/AppFeed/master/applicationFeed.json"

  class Error < StandardError; end
  class FeedUnavailableError < Error; end
  class ParseError < Error; end

  def initialize(http_client: Faraday.new)
    @http_client = http_client
  end

  def fetch_feed
    Rails.logger.info("Fetching Community Applications feed from #{FEED_URL}")

    response = @http_client.get(FEED_URL)

    unless response.success?
      raise FeedUnavailableError, "Failed to fetch feed: #{response.status} #{response.reason_phrase}"
    end

    parse_feed(response.body)
  rescue Faraday::Error => e
    raise FeedUnavailableError, "Network error fetching feed: #{e.message}"
  end

  def find_template_by_repository(repository)
    feed_data = fetch_feed

    # Search through applications to find matching repository
    feed_data["applications"]&.find do |app|
      normalize_repository(app["Repository"]) == normalize_repository(repository)
    end
  end

  def search_templates(query)
    feed_data = fetch_feed

    return [] unless feed_data["applications"]

    feed_data["applications"].select do |app|
      matches_search_query?(app, query.downcase)
    end
  end

  def convert_to_template(app_data)
    return unless app_data

    ::Template.new(
      name: app_data["Name"],
      repository: app_data["Repository"],
      network: app_data["Network"],
      category: app_data["Category"],
      banner: app_data["Icon"],
      webui: app_data["WebUI"],
      description: app_data["Overview"],
      xml_content: build_xml_from_app_data(app_data),
      source: "community",
      template_version: app_data["Date"],
      last_updated_at: parse_date(app_data["Date"]),
    )
  end

  private

  def parse_feed(json_content)
    JSON.parse(json_content)
  rescue JSON::ParserError => e
    raise ParseError, "Invalid JSON in feed: #{e.message}"
  end

  def normalize_repository(repository)
    return "" unless repository

    # Remove common prefixes and normalize
    normalized = repository.downcase
    # Remove registry prefixes but keep the image name structure
    normalized = normalized.gsub(%r{^(docker\.io/|ghcr\.io/|lscr\.io/)}, "")
    # Remove :latest tag
    normalized = normalized.gsub(/:latest$/, "")
    normalized
  end

  def matches_search_query?(app, query)
    return false unless app

    [
      app["Name"],
      app["Repository"],
      app["Overview"],
      app["Category"],
    ].compact.any? { |field| field.downcase.include?(query) }
  end

  def build_xml_from_app_data(app_data)
    # Build a basic XML structure from the app data
    # This would need to be more sophisticated in practice
    xml = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.Container(version: "2") do
        xml.Name(app_data["Name"])
        xml.Repository(app_data["Repository"])
        xml.Registry(app_data["Registry"]) if app_data["Registry"]
        xml.Network(app_data["Network"]) if app_data["Network"]
        xml.Privileged(app_data["Privileged"]) if app_data["Privileged"]
        xml.Support(app_data["Support"]) if app_data["Support"]
        xml.Project(app_data["Project"]) if app_data["Project"]
        xml.Overview(app_data["Overview"]) if app_data["Overview"]
        xml.Category(app_data["Category"]) if app_data["Category"]
        xml.WebUI(app_data["WebUI"]) if app_data["WebUI"]
        xml.Icon(app_data["Icon"]) if app_data["Icon"]
        xml.TemplateURL(app_data["TemplateURL"]) if app_data["TemplateURL"]
        xml.Date(app_data["Date"]) if app_data["Date"]

        # Add config elements if present
        app_data["Config"]&.each do |config|
          attrs = {}
          config.each { |k, v| attrs[k] = v unless k == "content" }
          xml.Config(attrs)
        end
      end
    end

    xml.to_xml
  end

  def parse_date(date_string)
    return unless date_string

    # Try to parse various date formats that might be in the feed
    Time.zone.parse(date_string)
  rescue ArgumentError
    # If it's a Unix timestamp
    Time.zone.at(date_string.to_i) if date_string.to_i > 0
  rescue StandardError
    nil
  end
end
