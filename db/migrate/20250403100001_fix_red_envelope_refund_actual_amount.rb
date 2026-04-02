# frozen_string_literal: true

# 修复历史红包退款订单缺少 actual_amount 的问题
# RefundExpiredRedEnvelopes 创建订单时漏设 actual_amount，导致"实际到账"显示 0
class FixRedEnvelopeRefundActualAmount < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE credit_orders
      SET actual_amount = amount,
          fee_rate = COALESCE(fee_rate, 0),
          fee_amount = COALESCE(fee_amount, 0)
      WHERE order_type = 'red_envelope_refund'
        AND (actual_amount IS NULL OR actual_amount = 0)
        AND amount > 0
    SQL
  end

  def down
    # 不可逆操作，无需回滚
  end
end
