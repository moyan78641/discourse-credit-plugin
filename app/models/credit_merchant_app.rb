# frozen_string_literal: true

class CreditMerchantApp < ActiveRecord::Base
  self.table_name = "credit_merchant_apps"

  has_many :products, class_name: "CreditProduct", foreign_key: :merchant_app_id

  validates :user_id, presence: true
  validates :app_name, presence: true
  validates :client_id, presence: true, uniqueness: true
  validates :client_secret, presence: true

  scope :active, -> { where(is_active: true) }
end
