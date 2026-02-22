# frozen_string_literal: true

class CreditRedEnvelope < ActiveRecord::Base
  self.table_name = "credit_red_envelopes"

  has_many :claims, class_name: "CreditRedEnvelopeClaim", foreign_key: :red_envelope_id

  validates :sender_id, presence: true
  validates :envelope_type, inclusion: { in: %w[fixed random] }
  validates :total_amount, numericality: { greater_than: 0 }
  validates :total_count, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[active finished expired] }

  scope :active, -> { where(status: "active") }
  scope :expired_refundable, -> { active.where("expires_at < ? AND remaining_amount > 0", Time.current) }

  def claimed_by?(user_id)
    claims.exists?(user_id: user_id)
  end

  def exhausted?
    remaining_count <= 0
  end
end
