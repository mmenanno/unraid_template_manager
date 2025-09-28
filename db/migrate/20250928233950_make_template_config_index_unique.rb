# frozen_string_literal: true

class MakeTemplateConfigIndexUnique < ActiveRecord::Migration[8.0]
  def change
    # Remove existing non-unique index
    remove_index(:template_configs, [:template_id, :name]) if index_exists?(:template_configs, [:template_id, :name])

    # Add unique index
    add_index(:template_configs, [:template_id, :name], unique: true)
  end
end
