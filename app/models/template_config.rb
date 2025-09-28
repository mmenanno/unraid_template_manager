# frozen_string_literal: true

class TemplateConfig < ApplicationRecord
  belongs_to :template

  validates :name, presence: true
  validates :config_type, presence: true
  validates :template_id, uniqueness: { scope: :name }

  scope :ordered, -> { order(:order_index, :name) }
  scope :ports, -> { where(config_type: "Port") }
  scope :paths, -> { where(config_type: "Path") }
  scope :variables, -> { where(config_type: "Variable") }

  def port?
    config_type == "Port"
  end

  def path?
    config_type == "Path"
  end

  def variable?
    config_type == "Variable"
  end

  def required?
    required == true
  end
end
