# frozen_string_literal: true

class TemplateChangesApplier
  class Error < StandardError; end
  class BackupError < Error; end
  class ApplyError < Error; end

  def initialize(template_comparison)
    @comparison = template_comparison
    @local_template = template_comparison.local_template
    @community_template = template_comparison.community_template
    @backup_directory = Rails.application.config.backup_directory
  end

  def apply!
    validate_comparison!
    ensure_backup_directory!

    ActiveRecord::Base.transaction do
      backup_original_template!
      apply_user_choices!
      update_local_template_file!
      @comparison.update!(status: "applied", applied_at: Time.current)
    end

    true
  rescue => e
    Rails.logger.error("Failed to apply template changes: #{e.message}")
    raise ApplyError, "Failed to apply changes: #{e.message}"
  end

  def preview_changes
    return {} if @comparison.user_choices.blank?

    preview = {
      basic_fields: {},
      configs: {},
      xml_preview: nil,
    }

    # Preview basic field changes
    @comparison.differences.each do |key, diff|
      next unless @comparison.user_choices[key] == "community"

      case diff["type"]
      when "basic_field"
        preview[:basic_fields][diff["field_name"]] = {
          from: diff["local"],
          to: diff["community"],
        }
      when "config"
        preview[:configs][diff["config_name"]] = build_config_preview(diff)
      when "new_config"
        preview[:configs][diff["config_name"]] = {
          action: "add",
          config: diff["community"],
        }
      when "removed_config"
        preview[:configs][diff["config_name"]] = {
          action: "remove",
          config: diff["local"],
        }
      end
    end

    # Generate XML preview
    preview[:xml_preview] = generate_updated_xml

    preview
  end

  private

  def validate_comparison!
    raise ApplyError, "Template comparison is not in reviewed status" unless @comparison.reviewed?
    raise ApplyError, "No user choices provided" if @comparison.user_choices.blank?
    raise ApplyError, "Local template file path not found" if @local_template.local_path.blank?
  end

  def ensure_backup_directory!
    FileUtils.mkdir_p(@backup_directory) unless Dir.exist?(@backup_directory)
  rescue => e
    raise BackupError, "Could not create backup directory: #{e.message}"
  end

  def backup_original_template!
    return unless File.exist?(@local_template.local_path)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    template_name = File.basename(@local_template.local_path, ".xml")
    backup_filename = "#{template_name}_backup_#{timestamp}.xml"
    backup_path = File.join(@backup_directory, backup_filename)

    # Check if backup already exists
    if File.exist?(backup_path)
      Rails.logger.warn("Backup file already exists: #{backup_path}")
      # Could prompt user here, but for now just proceed with timestamp
    end

    FileUtils.cp(@local_template.local_path, backup_path)
    Rails.logger.info("Backed up template to: #{backup_path}")

    backup_path
  rescue => e
    raise BackupError, "Failed to backup original template: #{e.message}"
  end

  def apply_user_choices!
    @comparison.differences.each do |key, diff|
      choice = @comparison.user_choices[key]
      next unless choice == "community"

      case diff["type"]
      when "basic_field"
        field_name = diff["field_name"].parameterize.underscore
        # Use manual edit if available, otherwise use community value
        value = @comparison.manual_edit_for_field(key) || diff["community"]
        @local_template.send("#{field_name}=", value)
      when "config", "new_config"
        # XML configs will be handled in XML generation
        next
      when "removed_config"
        # Config removal will be handled in XML generation
        next
      end
    end

    # Update XML content with new configuration
    @local_template.xml_content = generate_updated_xml
    @local_template.last_updated_at = Time.current
    @local_template.save!
  end

  def generate_updated_xml
    # Start with local template XML as base and apply community choices
    doc = Nokogiri::XML(@local_template.xml_content)

    # Apply basic field updates based on user choices
    @comparison.differences.each do |key, diff|
      choice = @comparison.user_choices[key]

      case diff["type"]
      when "basic_field"
        # Map field names to actual XML element names
        element_name = case key
        when "webui"
          "WebUI"
        when "network"
          "Network"
        when "description"
          "Overview"
        when "category"
          "Category"
        when "name"
          "Name"
        when "banner"
          "Icon"
        else
          diff["field_name"].camelize
        end

        field_element = doc.at(element_name)
        if field_element && choice == "community"
          # Use manual edit if available, otherwise use community value
          value = @comparison.manual_edit_for_field(key) || diff["community"] || ""
          # Convert category back to UnRAID format (hyphen-separated to colon-separated)
          value = convert_category_to_unraid_format(value) if key == "category"
          field_element.content = value
        end
      when "config"
        update_config_in_xml(doc, diff, key)
      when "new_config"
        add_config_to_xml(doc, diff) if choice == "community"
      when "removed_config"
        remove_config_from_xml(doc, diff) if choice == "community"
      end
    end

    doc.to_xml
  end

  def update_config_in_xml(doc, diff, config_key)
    config_name = diff["config_name"]
    config_node = doc.xpath("//Config[@Name='#{config_name}']").first
    return unless config_node

    # Check if there's a general choice for this config
    general_choice = @comparison.user_choices[config_key]

    # Handle field-level choices for this config
    diff["field_differences"].each do |field, change|
      field_choice_key = "#{config_key}_#{field}"
      field_choice = @comparison.user_choices[field_choice_key]

      # Use field-specific choice if available, otherwise fall back to general choice
      should_apply_community = (field_choice == "community") || (field_choice.nil? && general_choice == "community")

      next unless should_apply_community

      # Get the value to use: manual edit if available, otherwise community value
      field_key = "#{config_key}_#{field}"
      value_to_use = @comparison.manual_edit_for_field(field_key) || change["community"]

      case field
      when "target"
        config_node["Target"] = value_to_use.to_s if value_to_use
      when "default_value"
        config_node["Default"] = value_to_use.to_s if value_to_use
      when "actual_value"
        config_node.content = value_to_use.to_s if value_to_use
      when "mode"
        config_node["Mode"] = value_to_use.to_s if value_to_use
      when "description"
        config_node["Description"] = value_to_use.to_s if value_to_use
      when "required"
        config_node["Required"] = value_to_use.to_s unless value_to_use.nil?
      when "display"
        config_node["Display"] = value_to_use.to_s if value_to_use
      when "config_type"
        config_node["Type"] = value_to_use.to_s if value_to_use
      end
    end
  end

  def add_config_to_xml(doc, diff)
    config = diff["community"]
    container = doc.at("Container")

    config_node = Nokogiri::XML::Node.new("Config", doc)

    # Find the config key for this new config to check for manual edits
    config_key = diff.key?("config_name") ? diff["config_name"] : config["name"]

    config_node["Name"] = config["name"].to_s if config["name"]
    config_node["Type"] = (@comparison.manual_edit_for_field("#{config_key}_config_type") || config["config_type"]).to_s if config["config_type"]
    config_node["Target"] = (@comparison.manual_edit_for_field("#{config_key}_target") || config["target"]).to_s if config["target"]
    config_node["Default"] = (@comparison.manual_edit_for_field("#{config_key}_default_value") || config["default_value"]).to_s if config["default_value"]
    config_node["Mode"] = (@comparison.manual_edit_for_field("#{config_key}_mode") || config["mode"]).to_s if config["mode"]
    config_node["Description"] = (@comparison.manual_edit_for_field("#{config_key}_description") || config["description"]).to_s if config["description"]

    required_value = @comparison.manual_edit_for_field("#{config_key}_required") || config["required"]
    config_node["Required"] = required_value.to_s unless required_value.nil?

    config_node["Display"] = (@comparison.manual_edit_for_field("#{config_key}_display") || config["display"]).to_s if config["display"]

    container.add_child(config_node)
  end

  def remove_config_from_xml(doc, diff)
    config_name = diff["config_name"]
    config_node = doc.xpath("//Config[@Name='#{config_name}']").first
    config_node&.remove
  end

  def update_local_template_file!
    return if @local_template.local_path.blank?

    File.write(@local_template.local_path, @local_template.xml_content)
    Rails.logger.info("Updated template file: #{@local_template.local_path}")
  rescue => e
    raise ApplyError, "Failed to update template file: #{e.message}"
  end

  def build_config_preview(diff)
    preview = { action: "modify", changes: {} }

    diff["field_differences"].each do |field, change|
      preview[:changes][field] = {
        from: change["local"],
        to: change["community"],
      }
    end

    preview
  end

  def convert_category_to_unraid_format(category)
    return category if category.blank?

    # Convert community format (hyphen-separated) back to UnRAID format (colon-separated)
    # e.g., "Tools-Utilities" -> "Tools:Utilities"
    #       "MediaApp-Other" -> "MediaApp:Other"
    unraid_category = category.tr("-", ":")

    # For single-word categories (like "Downloaders"), UnRAID typically uses a trailing colon
    # Multi-word categories (like "Tools:Utilities") don't need the trailing colon
    if unraid_category.count(":") == 0
      unraid_category + ":"
    else
      unraid_category
    end
  end
end
