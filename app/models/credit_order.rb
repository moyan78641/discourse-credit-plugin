# frozen_string_literal: true

class CreditOrder < ActiveRecord::Base
  self.table_name = "credit_orders"

  # Order types
  TYPES = %w[
    receive payment transfer community online
    distribute red_envelope_send red_envelope_receive red_envelope_refund
  ].freeze

  # Statuses
  STATUSES = %w[success failed pending expired disputing refund refused].freeze

  validates :order_name, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :order_type, inclusion: { in: TYPES }

  scope :income_for, ->(uid) { where(payee_user_id: uid).where.not(payer_user_id: uid) }
  scope :expense_for, ->(uid) { where(payer_user_id: uid).where("payer_user_id > 0") }
  scope :successful, -> { where(status: "success") }
  scope :pending, -> { where(status: "pending") }
end
