# frozen_string_literal: true

class CreditCardKey < ActiveRecord::Base
  belongs_to :product, class_name: "CreditProduct", foreign_key: :product_id
  belongs_to :buyer, class_name: "User", foreign_key: :buyer_user_id, optional: true
  belongs_to :order, class_name: "CreditOrder", foreign_key: :order_id, optional: true

  scope :available, -> { where(status: "available") }
end
