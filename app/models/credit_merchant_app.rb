# frozen_string_literal: true

class CreditMerchantApp < ActiveRecord::Base
  self.table_name = "credit_merchant_apps"

  has_many :products, class_name: "CreditProduct", foreign_key: :merchant_app_id
  has_many :payment_transactions, class_name: "CreditPaymentTransaction", foreign_key: :merchant_app_id

  validates :user_id, presence: true
  validates :app_name, presence: true
  validates :client_id, presence: true, uniqueness: true
  validates :client_secret, presence: true

  scope :active, -> { where(is_active: true) }

  before_create :generate_token

  def generate_token!
    update!(token: self.class.new_token)
  end

  def secret_key
    Digest::SHA256.hexdigest(token)
  end

  private

  def generate_token
    self.token ||= self.class.new_token
  end

  def self.new_token
    "tk_#{SecureRandom.hex(24)}"
  end
end
