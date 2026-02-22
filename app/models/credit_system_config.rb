# frozen_string_literal: true

class CreditSystemConfig < ActiveRecord::Base
  self.table_name = "credit_system_configs"
  self.primary_key = "key"

  DEFAULTS = {
    "new_user_initial_credit" => { value: "100", desc: "新用户初始积分" },
    "new_user_protection_days" => { value: "7", desc: "新用户保护期（天）" },
    "tip_fee_rate" => { value: "0", desc: "打赏手续费率（0-1）" },
    "tip_min_amount" => { value: "1", desc: "打赏最小金额" },
    "tip_max_amount" => { value: "10000", desc: "打赏最大金额" },
    "merchant_fee_rate" => { value: "0.01", desc: "商户手续费率（0-1）" },
    "red_envelope_max_amount" => { value: "10000", desc: "单个红包最大金额" },
    "red_envelope_max_recipients" => { value: "100", desc: "单个红包最大人数" },
    "red_envelope_daily_limit" => { value: "10", desc: "每日发红包数量限制" },
    "red_envelope_fee_rate" => { value: "0.01", desc: "红包手续费率（0-1）" },
    "red_envelope_expire_hours" => { value: "24", desc: "红包过期时间（小时）" },
  }.freeze

  def self.get(key)
    find_by(key: key)&.value || DEFAULTS.dig(key, :value)
  end

  def self.get_i(key)
    get(key).to_i
  end

  def self.get_f(key)
    get(key).to_f
  end

  def self.seed_defaults!
    DEFAULTS.each do |key, cfg|
      find_or_create_by!(key: key) do |c|
        c.value = cfg[:value]
        c.description = cfg[:desc]
      end
    end
  end
end
