# frozen_string_literal: true

class CreditWallet < ActiveRecord::Base
  self.table_name = "credit_wallets"

  validates :user_id, presence: true, uniqueness: true
  validates :sign_key, presence: true

  def has_pay_key?
    pay_key.present?
  end

  def pay_level
    config = CreditPayConfig.for_score(pay_score)
    config&.level || 0
  end

  def pay_level_name
    CreditPayConfig.level_name(pay_level)
  end

  def pay_config
    CreditPayConfig.for_score(pay_score)
  end
end
