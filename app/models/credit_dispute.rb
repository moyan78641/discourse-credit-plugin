# frozen_string_literal: true

class CreditDispute < ActiveRecord::Base
  self.table_name = "credit_disputes"

  STATUSES = %w[disputing resolved rejected auto_refunded].freeze

  belongs_to :order, class_name: "CreditOrder", foreign_key: :order_id, optional: true

  validates :reason, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "disputing") }
  scope :expired, -> { active.where("deadline_at < ?", Time.current) }
end
