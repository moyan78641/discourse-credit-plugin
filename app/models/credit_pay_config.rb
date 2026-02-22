# frozen_string_literal: true

class CreditPayConfig < ActiveRecord::Base
  self.table_name = "credit_pay_configs"

  LEVEL_NAMES = {
    0 => "普通会员",
    1 => "黄金会员",
    2 => "白金会员",
    3 => "黑金会员",
  }.freeze

  DEFAULTS = [
    { level: 0, min_score: 0, max_score: 1000, fee_rate: 0.01 },
    { level: 1, min_score: 1000, max_score: 5000, fee_rate: 0.008 },
    { level: 2, min_score: 5000, max_score: 20000, fee_rate: 0.005 },
    { level: 3, min_score: 20000, max_score: nil, fee_rate: 0 },
  ].freeze

  validates :level, presence: true, uniqueness: true

  def self.level_name(level)
    LEVEL_NAMES[level] || "未知等级"
  end

  def self.for_score(score)
    where("min_score <= ?", score)
      .where("max_score IS NULL OR max_score > ?", score)
      .order(min_score: :desc)
      .first
  end

  def self.seed_defaults!
    DEFAULTS.each do |cfg|
      find_or_create_by!(level: cfg[:level]) do |c|
        c.min_score = cfg[:min_score]
        c.max_score = cfg[:max_score]
        c.fee_rate = cfg[:fee_rate]
      end
    end
  end
end
