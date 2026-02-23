# frozen_string_literal: true

class CreditPaymentTransaction < ActiveRecord::Base
  self.table_name = "credit_payment_transactions"

  STATUSES = %w[pending processing completed failed cancelled refunded expired].freeze

  belongs_to :merchant_app, class_name: "CreditMerchantApp", foreign_key: :merchant_app_id
  belongs_to :order, class_name: "CreditOrder", foreign_key: :credit_order_id, optional: true

  validates :transaction_id, presence: true, uniqueness: true
  validates :external_reference, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }

  def expired?
    expires_at.present? && expires_at < Time.current && status == "pending"
  end

  def completable?
    status == "pending" && !expired?
  end
end
