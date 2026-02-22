# frozen_string_literal: true

class CreditDispute < ActiveRecord::Base
  self.table_name = "credit_disputes"

  validates :order_id, presence: true, uniqueness: true
  validates :initiator_user_id, presence: true
  validates :reason, presence: true
  validates :status, inclusion: { in: %w[disputing refund closed] }

  scope :active, -> { where(status: "disputing") }
end
