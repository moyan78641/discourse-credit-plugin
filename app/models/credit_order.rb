# frozen_string_literal: true

class CreditOrder < ActiveRecord::Base
  self.table_name = "credit_orders"

  PAYER_FEE_ORDER_TYPES = %w[tip red_envelope_send].freeze
  PAYEE_FEE_ORDER_TYPES = %w[product].freeze

  # Order types (v2: 去掉 transfer/online/distribute, 新增 tip/product)
  TYPES = %w[
    receive payment community distribute
    tip product product_refund dispute_compensation
    red_envelope_send red_envelope_receive red_envelope_refund
  ].freeze

  STATUSES = %w[success failed pending expired refunded].freeze

  DELIVERY_STATUSES = %w[pending_delivery processing delivered refunded].freeze

  has_one :dispute, class_name: "CreditDispute", foreign_key: :order_id

  validates :order_name, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :order_type, inclusion: { in: TYPES }

  scope :income_for, ->(uid) { where(payee_user_id: uid).where.not(payer_user_id: uid) }
  scope :expense_for, ->(uid) { where(payer_user_id: uid).where("payer_user_id > 0") }
  scope :successful, -> { where(status: "success") }
  scope :pending, -> { where(status: "pending") }

  before_create :generate_order_no

  def fee_bearer
    return "payer" if PAYER_FEE_ORDER_TYPES.include?(order_type)
    return "payee" if PAYEE_FEE_ORDER_TYPES.include?(order_type)

    "none"
  end

  def effective_actual_amount
    actual = actual_amount.to_f
    actual.positive? ? actual : amount.to_f
  end

  def effective_display_amount_for(user_id)
    is_income_for_user = payee_user_id == user_id && payer_user_id != user_id
    return effective_actual_amount if is_income_for_user

    base_amount = amount.to_f
    return base_amount + fee_amount.to_f if PAYER_FEE_ORDER_TYPES.include?(order_type)

    base_amount
  end

  def as_detail_json(current_user_id)
    is_income = payee_user_id == current_user_id && payer_user_id != current_user_id
    {
      id: id,
      order_no: order_no,
      order_name: order_name,
      order_type: order_type,
      amount: amount.to_f,
      fee_rate: fee_rate.to_f,
      fee_amount: fee_amount.to_f,
      actual_amount: effective_actual_amount,
      display_amount: effective_display_amount_for(current_user_id),
      fee_bearer: fee_bearer,
      status: status,
      remark: remark,
      payer_user_id: payer_user_id,
      payer_username: payer_user_id > 0 ? (User.find_by(id: payer_user_id)&.username || "未知") : "系统",
      payee_user_id: payee_user_id,
      payee_username: payee_user_id > 0 ? (User.find_by(id: payee_user_id)&.username || "未知") : "系统",
      is_income: is_income,
      created_at: created_at&.iso8601,
      trade_time: trade_time&.iso8601,
    }
  end

  private

  def generate_order_no
    return if order_no.present?
    self.order_no = "C#{Time.current.strftime('%Y%m%d%H%M%S')}#{SecureRandom.hex(4).upcase}"
  end
end
