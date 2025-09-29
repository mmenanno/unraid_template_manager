# frozen_string_literal: true

class AddCommunityRepositoryToTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column(:templates, :community_repository, :string)
  end
end
