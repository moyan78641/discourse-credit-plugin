# frozen_string_literal: true

class CreditRedEnvelopeClaim < ActiveRecord::Base
  self.table_name = "credit_red_envelope_claims"

  belongs_to :red_envelope, class_name: "CreditRedEnvelope", foreign_key: :red_envelope_id

  validates :red_envelope_id, presence: true
  validates :user_id, presence: true
  validates :amount, numericality: { greater_than: 0 }
end
