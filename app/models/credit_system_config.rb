# frozen_string_literal: true

class CreditSystemConfig < ActiveRecord::Base
  self.table_name = "credit_system_configs"
  self.primary_key = "key"

  DEFAULTS = {
    "new_user_initial_credit" => { value: "100", desc: "新用户初始积分" },
    "new_user_protection_days" => { value: "7", desc: "新用户保护期（天）" },
    "daily_transfer_limit" => { value: "1000", desc: "每日转账限额" },
    "transfer_fee_rate" => { value: "0", desc: "转账手续费率（0-1）" },
    "merchant_fee_rate" => { value: "0.01", desc: "商户手续费率（0-1）" },
    "merchant_order_expire_minutes" => { value: "30", desc: "商户订单过期时间（分钟）" },
    "dispute_time_window_hours" => { value: "72", desc: "争议时间窗口（小时）" },
    "dispute_auto_refund_hours" => { value: "168", desc: "争议自动退款时间（小时）" },
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
