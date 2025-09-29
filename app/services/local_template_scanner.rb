# frozen_string_literal: true

class LocalTemplateScanner
  class Error < StandardError; end
  class DirectoryNotFoundError < Error; end
  class FileReadError < Error; end

  def initialize(template_directory: Rails.application.config.template_directory)
    @template_directory = template_directory
  end

  def scan_templates
    validate_directory!

    xml_files = Dir.glob(File.join(@template_directory, "*.xml"))
    Rails.logger.info("Found #{xml_files.size} XML files in #{@template_directory}")

    xml_files.filter_map do |file_path|
      process_template_file(file_path)
    rescue FileReadError => e
      Rails.logger.error("Failed to process #{file_path}: #{e.message}")
      nil
    end
  end

  def find_template_by_name(name)
    file_path = File.join(@template_directory, "#{name}.xml")
    return unless File.exist?(file_path)

    process_template_file(file_path)
  end

  def sync_local_templates!
    scanned_templates = scan_templates
    existing_repositories = Template.local.pluck(:repository)
    results = { created: 0, updated: 0, removed: 0 }

    ActiveRecord::Base.transaction do
      scanned_templates.each do |template_data|
        template = Template.local.find_or_initialize_by(repository: template_data[:repository])

        if template.persisted?
          # Update existing template if XML content has changed
          if template.xml_content != template_data[:xml_content]
            template.update!(template_data.merge(last_updated_at: Time.current))
            template.sync_configs_from_xml!
            results[:updated] += 1
            Rails.logger.info("Updated template: #{template.name}")
          end
        else
          # Create new template
          template.assign_attributes(template_data)
          template.save!
          template.sync_configs_from_xml!
          results[:created] += 1
          Rails.logger.info("Created template: #{template.name}")
        end
      end

      # Mark templates as inactive if they're no longer on disk
      current_repositories = scanned_templates.map { |t| t[:repository] }
      missing_repositories = existing_repositories - current_repositories

      if missing_repositories.any?
        templates_to_update = Template.local.where(repository: missing_repositories)
        templates_to_update.find_each do |template|
          template.update!(
            status: "inactive",
            last_updated_at: Time.current,
          )
        end
        results[:removed] = missing_repositories.size
        Rails.logger.info("Marked #{missing_repositories.size} templates as inactive")
      end
    end

    results
  end

  private

  def validate_directory!
    unless File.directory?(@template_directory)
      raise DirectoryNotFoundError,
        "Template directory does not exist: #{@template_directory}. " \
          "Ensure the UnRAID template directory is mapped to /templates volume. " \
          "Use: -v /boot/config/plugins/dockerMan/templates-user:/templates"
    end

    unless File.readable?(@template_directory)
      raise DirectoryNotFoundError, "Template directory is not readable: #{@template_directory}"
    end
  end

  def process_template_file(file_path)
    xml_content = read_file_safely(file_path)
    return if xml_content.blank?

    parsed_xml = parse_xml_safely(xml_content, file_path)
    return unless parsed_xml

    extract_template_data(parsed_xml, xml_content, file_path)
  rescue => e
    raise FileReadError, "Error processing #{file_path}: #{e.message}"
  end

  def read_file_safely(file_path)
    File.read(file_path, encoding: "utf-8")
  rescue Encoding::InvalidByteSequenceError
    # Try reading as binary and force UTF-8 encoding
    File.read(file_path, encoding: "binary").force_encoding("utf-8")
  rescue => e
    raise FileReadError, "Could not read file #{file_path}: #{e.message}"
  end

  def parse_xml_safely(xml_content, file_path)
    Nokogiri::XML(xml_content) do |config|
      config.strict.nonet
    end
  rescue Nokogiri::XML::SyntaxError => e
    Rails.logger.warn("Invalid XML in #{file_path}: #{e.message}")
    nil
  end

  def extract_template_data(parsed_xml, xml_content, file_path)
    container = parsed_xml.at("Container")
    return unless container

    {
      name: extract_text(container, "Name"),
      repository: extract_text(container, "Repository"),
      network: extract_text(container, "Network"),
      category: extract_text(container, "Category"),
      banner: extract_text(container, "Icon"),
      webui: extract_text(container, "WebUI"),
      description: extract_text(container, "Overview"),
      xml_content: xml_content,
      local_path: file_path,
      source: "local",
      status: "active",
      template_version: extract_text(container, "Date"),
      last_updated_at: File.mtime(file_path),
    }
  end

  def extract_text(container, element_name)
    element = container.at(element_name)
    element&.text&.strip
  end
end
