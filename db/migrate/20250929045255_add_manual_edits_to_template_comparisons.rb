# frozen_string_literal: true

class AddManualEditsToTemplateComparisons < ActiveRecord::Migration[8.0]
  def change
    add_column(:template_comparisons, :manual_edits, :json, default: {})
  end
end
