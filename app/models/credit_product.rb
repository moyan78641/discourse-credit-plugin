# frozen_string_literal: true

class CreditProduct < ActiveRecord::Base
  self.table_name = "credit_products"

  belongs_to :merchant_app, class_name: "CreditMerchantApp", foreign_key: :merchant_app_id

  validates :name, presence: true
  validates :price, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[active inactive] }

  scope :active, -> { where(status: "active") }

  def in_stock?
    stock == -1 || stock > 0
  end
end
