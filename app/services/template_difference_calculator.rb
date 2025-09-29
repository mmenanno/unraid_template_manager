# frozen_string_literal: true

class TemplateDifferenceCalculator
  class Error < StandardError; end

  def initialize(local_template, community_template)
    @local_template = local_template
    @community_template = community_template
  end

  def calculate
    return {} if @local_template.nil? || @community_template.nil?

    differences = {}

    # Compare basic template fields
    compare_basic_fields(differences)

    # Compare XML structure and configs
    compare_xml_configs(differences)

    differences
  end

  private

  def compare_basic_fields(differences)
    basic_fields = ["name", "network", "category", "banner", "webui", "description", "template_version"]

    basic_fields.each do |field|
      local_raw = @local_template.send(field)
      community_raw = @community_template.send(field)

      # Skip normalization if values are exactly the same
      if local_raw == community_raw
        next
      end

      local_value = normalize_field_value(local_raw, field)
      community_value = normalize_field_value(community_raw, field)

      next if local_value == community_value

      differences[field] = {
        "type" => "basic_field",
        "local" => local_value,
        "community" => community_value,
        "field_name" => field.humanize,
      }
    end
  end

  def compare_xml_configs(differences)
    local_configs = extract_configs_from_template(@local_template)
    community_configs = extract_configs_from_template(@community_template)

    # Find configs that exist in both templates
    common_config_names = local_configs.keys & community_configs.keys

    # Compare common configs
    common_config_names.each do |config_name|
      local_config = local_configs[config_name]
      community_config = community_configs[config_name]

      config_diff = compare_config_elements(local_config, community_config)
      next if config_diff.none?

      differences["config_#{config_name}"] = {
        "type" => "config",
        "config_name" => config_name,
        "local" => local_config,
        "community" => community_config,
        "field_differences" => config_diff,
      }
    end

    # Find configs only in community template (new configs)
    new_configs = community_configs.keys - local_configs.keys
    new_configs.each do |config_name|
      differences["new_config_#{config_name}"] = {
        "type" => "new_config",
        "config_name" => config_name,
        "community" => community_configs[config_name],
        "field_name" => "New Config: #{config_name}",
      }
    end

    # Find configs only in local template (removed configs)
    removed_configs = local_configs.keys - community_configs.keys
    removed_configs.each do |config_name|
      differences["removed_config_#{config_name}"] = {
        "type" => "removed_config",
        "config_name" => config_name,
        "local" => local_configs[config_name],
        "field_name" => "Removed Config: #{config_name}",
      }
    end
  end

  def compare_config_elements(local_config, community_config)
    field_differences = {}
    config_fields = ["target", "default_value", "actual_value", "mode", "description", "required", "display"]

    config_fields.each do |field|
      local_value = normalize_value(local_config[field.to_sym])
      community_value = normalize_value(community_config[field.to_sym])

      next if local_value == community_value

      field_differences[field] = {
        "local" => local_value,
        "community" => community_value,
      }
    end

    field_differences
  end

  def extract_configs_from_template(template)
    configs = {}

    begin
      parsed_xml = Nokogiri::XML(template.xml_content)
      parsed_xml.xpath("//Config").each do |config_node|
        name = config_node["Name"]
        next unless name

        # Extract actual value from element content
        actual_value = config_node.text&.strip
        default_value = config_node["Default"]

        # For community templates, if no actual value is set but there's a default,
        # use the default as the actual value (since that's what would be used)
        if actual_value.blank? && default_value.present? && template.community?
          actual_value = default_value
        end

        configs[name] = {
          name: name,
          config_type: config_node["Type"],
          target: config_node["Target"],
          default_value: default_value,
          actual_value: actual_value,
          mode: config_node["Mode"],
          description: config_node["Description"],
          required: config_node["Required"] == "true",
          display: config_node["Display"] || "always",
        }
      end
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.error("Failed to parse XML for template #{template.name}: #{e.message}")
    end

    configs
  end

  def normalize_field_value(value, field_name)
    return if value.blank?

    normalized = normalize_value(value)
    return if normalized.nil?

    case field_name
    when "category"
      normalize_category(normalized)
    when "description"
      # Strip HTML/UnRAID tags for comparison (but preserve original formatting in XML)
      strip_unraid_tags(normalized)
    else
      normalized
    end
  end

  def normalize_value(value)
    return if value.blank?

    # Normalize whitespace and empty strings
    normalized = value.to_s.strip
    normalized.empty? ? nil : normalized
  end

  def normalize_category(category)
    return if category.blank?

    # Remove any trailing content after the main category
    # e.g., "Tools:Utilities spotlight:" -> "Tools:Utilities"
    # e.g., "Downloaders: MediaApp:Video" -> "Downloaders:"
    normalized = category.split(/\s+/).first

    # Convert UnRAID format (colon-separated) to Community format (hyphen-separated)
    # e.g., "Tools:Utilities" -> "Tools-Utilities"
    #       "MediaApp:Other" -> "MediaApp-Other"
    #       "Downloaders:" -> "Downloaders"
    normalized = normalized.tr(":", "-")

    # Remove any trailing separators (this handles both : and - from the conversion)
    normalized = normalized.gsub(/[-:]+$/, "")

    normalized.empty? ? nil : normalized
  end

  def strip_unraid_tags(text)
    return if text.blank?

    # Strip UnRAID-style tags like [h3]...[/h3], [b]...[/b], [i]...[/i], etc.
    # This allows comparison of content regardless of formatting tags
    # e.g., "[h3]MongoDB[/h3]MongoDB" becomes "MongoDBMongoDB"
    stripped = text.gsub(/\[[^\]]*\]/, "")

    # Normalize whitespace after tag removal
    stripped = stripped.gsub(/\s+/, " ").strip

    stripped.empty? ? nil : stripped
  end
end
