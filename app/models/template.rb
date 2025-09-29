# frozen_string_literal: true

class Template < ApplicationRecord
  has_many :local_comparisons,
    class_name: "TemplateComparison",
    foreign_key: "local_template_id",
    dependent: :destroy,
    inverse_of: :local_template
  has_many :community_comparisons,
    class_name: "TemplateComparison",
    foreign_key: "community_template_id",
    dependent: :destroy,
    inverse_of: :community_template
  has_many :template_configs, dependent: :destroy

  validates :name, presence: true
  validates :repository, presence: true
  validates :xml_content, presence: true
  validates :status, presence: true, inclusion: { in: ["active", "inactive"] }
  validates :source, presence: true, inclusion: { in: ["local", "community"] }
  validates :repository, uniqueness: { scope: :source }
  validates :not_in_community, inclusion: { in: [true, false] }

  scope :local, -> { where(source: "local") }
  scope :community, -> { where(source: "community") }
  scope :active, -> { where(status: "active") }
  scope :in_community, -> { where(not_in_community: false) }
  scope :not_in_community, -> { where(not_in_community: true) }
  scope :with_pending_comparisons, -> { joins(:local_comparisons).where(template_comparisons: { status: "pending" }) }
  scope :with_reviewed_comparisons, -> { joins(:local_comparisons).where(template_comparisons: { status: "reviewed" }) }
  scope :with_applied_comparisons, -> { joins(:local_comparisons).where(template_comparisons: { status: "applied" }) }
  scope :without_comparisons, -> { left_joins(:local_comparisons).where(template_comparisons: { id: nil }) }

  def local?
    source == "local"
  end

  def community?
    source == "community"
  end

  def should_sync_with_community?
    local? && !not_in_community?
  end

  def has_comparison?
    return false unless local?

    TemplateComparison.exists?(local_template: self)
  end

  def latest_comparison
    return unless local?

    local_comparisons.order(:last_compared_at).last
  end

  def find_or_create_comparison_with(community_template)
    return unless local? && community_template.community? && should_sync_with_community?

    comparison = TemplateComparison.find_or_initialize_by(
      local_template: self,
      community_template: community_template,
    )

    if comparison.persisted?
      # Update existing comparison
    else
      # Create new comparison
      comparison.save!
    end
    comparison.calculate_differences!

    comparison
  end

  def matching_community_template
    return unless local?

    Template.community.find_by(repository: repository)
  end

  def parse_xml
    @parsed_xml ||= Nokogiri::XML(xml_content)
  end

  def extract_configs_from_xml
    configs = []
    parse_xml.xpath("//Config").each_with_index do |config_node, index|
      configs << {
        name: config_node["Name"],
        config_type: config_node["Type"],
        target: config_node["Target"],
        default_value: config_node["Default"],
        mode: config_node["Mode"],
        description: config_node["Description"],
        required: config_node["Required"] == "true",
        display: config_node["Display"] || "always",
        order_index: index,
      }
    end
    configs
  end

  def sync_configs_from_xml!
    return if xml_content.blank?

    begin
      # Clear existing configs
      template_configs.destroy_all

      # Use the existing extraction method
      configs_data = extract_configs_from_xml

      # Filter out invalid configs and deduplicate by name (keep last occurrence)
      valid_configs = configs_data.select { |config| config[:name].present? }
      deduplicated_configs = valid_configs.reverse.uniq { |config| config[:name] }.reverse

      if deduplicated_configs.size < valid_configs.size
        Rails.logger.warn("Removed #{valid_configs.size - deduplicated_configs.size} duplicate configs for template: #{name}")
      end

      template_configs.create!(deduplicated_configs) if deduplicated_configs.any?

      Rails.logger.info("Synced #{deduplicated_configs.size} configs for template: #{name}")
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.error("Failed to parse XML for template #{name}: #{e.message}")
      raise
    rescue => e
      Rails.logger.error("Failed to sync configs for template #{name}: #{e.message}")
      raise
    end
  end
end
