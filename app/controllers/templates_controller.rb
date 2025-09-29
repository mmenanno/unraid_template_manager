# frozen_string_literal: true

class TemplatesController < ApplicationController
  before_action :find_template, only: [:show, :update]

  def index
    @sort_by = params[:sort_by] || "name"
    @sort_direction = params[:sort_direction] || "asc"
    @status_filter = params[:status_filter] || "all"
    @search_query = params[:search].to_s.strip

    # Define valid sort options
    valid_sort_options = {
      "name" => "name",
      "repository" => "repository",
      "updated" => "last_updated_at",
    }

    # Fallback to name if invalid sort option
    sort_column = valid_sort_options[@sort_by] || "name"
    direction = ["asc", "desc"].include?(@sort_direction) ? @sort_direction : "asc"

    # Start with base scope
    @local_templates = Template.local.active.includes(:local_comparisons)

    # Apply status filtering
    case @status_filter
    when "needs_review"
      @local_templates = @local_templates.with_pending_comparisons
    when "ready_to_apply"
      @local_templates = @local_templates.with_reviewed_comparisons
    when "up_to_date"
      @local_templates = @local_templates.with_applied_comparisons
    when "not_in_community"
      @local_templates = @local_templates.not_in_community
    when "no_comparison"
      @local_templates = @local_templates.without_comparisons
      # "all" - no additional filtering
    end

    # Apply search filtering
    if @search_query.present?
      @local_templates = @local_templates.where(
        "LOWER(name) LIKE ? OR LOWER(repository) LIKE ? OR LOWER(description) LIKE ?",
        "%#{@search_query.downcase}%",
        "%#{@search_query.downcase}%",
        "%#{@search_query.downcase}%",
      )
    end

    # Apply sorting
    @local_templates = @local_templates.order("#{sort_column} #{direction}")

    # Calculate stats based on filtered templates
    @filtered_templates_count = @local_templates.count

    # Count templates with pending reviews (templates that have at least one pending comparison)
    @filtered_pending_count = 0
    @filtered_up_to_date_count = 0

    @local_templates.each do |template|
      if template.not_in_community?
        # Templates not in community are considered "up to date" for stats purposes
        @filtered_up_to_date_count += 1
      elsif template.has_comparison?
        comparison = template.latest_comparison
        if comparison.pending?
          @filtered_pending_count += 1
        else
          @filtered_up_to_date_count += 1
        end
      else
        # Templates without comparisons are considered "up to date" for stats purposes
        @filtered_up_to_date_count += 1
      end
    end

    # Keep the original pending count for the header button
    @pending_comparisons_count = TemplateComparison.pending.count
    @recent_syncs = Template.local.order(last_updated_at: :desc).limit(5)
  end

  def show
    @comparison = @template.latest_comparison if @template.local?
  end

  def update
    if @template.local? && @template.update(template_params)
      # Trigger a new community sync for this template to test the new matching
      SyncCommunityTemplatesJob.perform_later
      redirect_to(@template, notice: I18n.t("templates.community_matching_updated"))
    else
      redirect_to(@template, alert: I18n.t("templates.community_matching_failed"))
    end
  end

  def sync
    SyncLocalTemplatesJob.perform_later
    redirect_path = params[:redirect_to] || templates_path
    redirect_to(redirect_path, notice: I18n.t("templates.sync_started"))
  end

  private

  def find_template
    @template = Template.find(params[:id])
  end

  def template_params
    params.expect(template: [:community_repository, :not_in_community])
  end
end
