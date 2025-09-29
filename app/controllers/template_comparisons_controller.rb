# frozen_string_literal: true

class TemplateComparisonsController < ApplicationController
  before_action :find_comparison, only: [:show, :update, :apply, :preview_diff]

  def index
    @pending_comparisons = TemplateComparison.pending.includes(:local_template, :community_template)
    @reviewed_comparisons = TemplateComparison.reviewed.recent.limit(10).includes(:local_template, :community_template)
  end

  def show
    @differences = @comparison.differences || {}
    @user_choices = @comparison.user_choices || {}
    @manual_edits = @comparison.manual_edits || {}
  end

  def update
    user_choices = permitted_user_choices
    manual_edits = permitted_manual_edits

    @comparison.user_choices = user_choices
    @comparison.manual_edits = manual_edits
    @comparison.status = "reviewed"

    if @comparison.save
      redirect_to(@comparison, notice: I18n.t("template_comparisons.choices_saved"))
    else
      @differences = @comparison.differences || {}
      @user_choices = @comparison.user_choices || {}
      render(:show, status: :unprocessable_entity)
    end
  end

  def preview_diff
    require "diffy"

    applier = TemplateChangesApplier.new(@comparison)
    original_xml = @comparison.local_template.xml_content
    updated_xml = applier.send(:generate_updated_xml)

    # Format XML for better readability
    original_formatted = format_xml(original_xml)
    updated_formatted = format_xml(updated_xml)

    # Generate HTML diff using Diffy
    diff_html = Diffy::Diff.new(
      original_formatted,
      updated_formatted,
      context: 3,
      include_plus_and_minus_in_html: true,
    ).to_s(:html)

    @diff_data = {
      original: original_formatted,
      updated: updated_formatted,
      diff_html: diff_html,
      changes_summary: applier.preview_changes,
      has_changes: original_formatted != updated_formatted,
    }

    render(json: @diff_data)
  end

  def apply
    if @comparison.apply_changes!
      redirect_to(template_comparisons_path, notice: I18n.t("template_comparisons.changes_applied"))
    else
      redirect_to(@comparison, alert: I18n.t("template_comparisons.apply_failed"))
    end
  end

  private

  def find_comparison
    @comparison = TemplateComparison.find(params[:id])
  end

  def permitted_user_choices
    # Permit only the fields that exist in the current comparison's differences
    allowed_fields = @comparison.differences&.keys || []

    # For config differences, also allow field-level choices
    field_level_choices = []
    @comparison.differences&.each do |key, diff|
      next unless diff["type"] == "config" && diff["field_differences"]

      diff["field_differences"].keys.each do |field|
        field_level_choices << "#{key}_#{field}"
      end
    end

    params.expect(template_comparison: [*(allowed_fields + field_level_choices)])
  end

  def permitted_manual_edits
    # Permit manual edits for any field that has a community choice
    allowed_fields = []

    @comparison.differences&.each do |key, diff|
      # Basic fields
      allowed_fields << key

      # Config field-level edits
      next unless diff["type"] == "config" && diff["field_differences"]

      diff["field_differences"].keys.each do |field|
        allowed_fields << "#{key}_#{field}"
      end
    end

    manual_edit_params = params[:manual_edits] || {}
    manual_edit_params.permit(*allowed_fields)
  end

  def format_xml(xml_content)
    # Parse and reformat XML for better diff readability
    doc = Nokogiri::XML(xml_content)
    doc.to_xml(indent: 2)
  rescue Nokogiri::XML::SyntaxError
    # If XML is malformed, return as-is
    xml_content
  end
end
