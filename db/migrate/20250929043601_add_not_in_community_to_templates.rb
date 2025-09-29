# frozen_string_literal: true

class AddNotInCommunityToTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column(:templates, :not_in_community, :boolean, default: false, null: false)
    add_index(:templates, :not_in_community)
  end
end
