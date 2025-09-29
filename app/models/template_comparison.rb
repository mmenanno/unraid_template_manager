# frozen_string_literal: true

class TemplateComparison < ApplicationRecord
  belongs_to :local_template, class_name: "Template"
  belongs_to :community_template, class_name: "Template"

  validates :status, presence: true, inclusion: { in: ["pending", "reviewed", "applied"] }
  validates :local_template_id, uniqueness: { scope: :community_template_id }

  scope :pending, -> { where(status: "pending") }
  scope :reviewed, -> { where(status: "reviewed") }
  scope :applied, -> { where(status: "applied") }
  scope :recent, -> { order(last_compared_at: :desc) }

  def pending?
    status == "pending"
  end

  def reviewed?
    status == "reviewed"
  end

  def applied?
    status == "applied"
  end

  def has_differences?
    differences.present? && differences.any?
  end

  def user_choices_for_field(field_name)
    return if user_choices.blank?

    user_choices[field_name]
  end

  def set_user_choice(field_name, choice)
    self.user_choices ||= {}
    self.user_choices[field_name] = choice
  end

  def manual_edit_for_field(field_name)
    return if manual_edits.blank?

    manual_edits[field_name]
  end

  def set_manual_edit(field_name, value)
    self.manual_edits ||= {}
    self.manual_edits[field_name] = value
  end

  def has_manual_edit?(field_name)
    manual_edits.present? && manual_edits[field_name].present?
  end

  def calculate_differences!
    differ = TemplateDifferenceCalculator.new(local_template, community_template)
    self.differences = differ.calculate
    self.last_compared_at = Time.current
    save!
  end

  def apply_changes?
    return false unless reviewed?

    applier = TemplateChangesApplier.new(self)
    if applier.apply!
      update!(status: "applied", applied_at: Time.current)
      true
    else
      false
    end
  end

  def apply_changes!
    return false unless reviewed?

    applier = TemplateChangesApplier.new(self)
    applier.apply!
  end

  def preview_changes
    return {} unless reviewed? && user_choices.present?

    applier = TemplateChangesApplier.new(self)
    applier.preview_changes
  end
end
