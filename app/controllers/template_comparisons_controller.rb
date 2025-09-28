# frozen_string_literal: true

class TemplateComparisonsController < ApplicationController
  before_action :find_comparison, only: [:show, :update, :apply]

  def index
    @pending_comparisons = TemplateComparison.pending.includes(:local_template, :community_template)
    @reviewed_comparisons = TemplateComparison.reviewed.recent.limit(10).includes(:local_template, :community_template)
  end

  def show
    @differences = @comparison.differences || {}
    @user_choices = @comparison.user_choices || {}
  end

  def update
    user_choices = permitted_user_choices
    @comparison.user_choices = user_choices
    @comparison.status = "reviewed"

    if @comparison.save
      redirect_to(@comparison, notice: I18n.t("template_comparisons.choices_saved"))
    else
      @differences = @comparison.differences || {}
      @user_choices = @comparison.user_choices || {}
      render(:show, status: :unprocessable_entity)
    end
  end

  def apply
    if @comparison.apply_changes!
      redirect_to(templates_path, notice: I18n.t("template_comparisons.changes_applied"))
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
    params.expect(template_comparison: [*allowed_fields])
  end
end
