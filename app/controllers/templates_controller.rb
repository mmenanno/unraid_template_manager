# frozen_string_literal: true

class TemplatesController < ApplicationController
  def index
    @local_templates = Template.local.active.includes(:local_comparisons)
    @pending_comparisons_count = TemplateComparison.pending.count
    @recent_syncs = Template.local.order(last_updated_at: :desc).limit(5)
  end

  def show
    @template = Template.find(params[:id])
    @comparison = @template.latest_comparison if @template.local?
  end

  def sync
    SyncLocalTemplatesJob.perform_later
    redirect_to(templates_path, notice: I18n.t("templates.sync_started"))
  end
end
