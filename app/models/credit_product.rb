# frozen_string_literal: true

class CreditProduct < ActiveRecord::Base
  self.table_name = "credit_products"

  # v2: 商品直接挂用户，不再需要 merchant_app
  belongs_to :owner, class_name: "User", foreign_key: :user_id, optional: true
  has_many :card_keys, class_name: "CreditCardKey", foreign_key: :product_id

  validates :name, presence: true
  validates :price, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[active inactive] }

  scope :active, -> { where(status: "active") }

  def in_stock?
    return true if stock == -1
    if auto_delivery
      card_keys.available.count > 0
    else
      stock > 0
    end
  end
end
