# frozen_string_literal: true

class AddDeliveryAndDisputeFields < ActiveRecord::Migration[7.0]
  def change
    # 订单增加发货状态 (非卡密商品: pending_delivery/processing/delivered/refunded)
    add_column :credit_orders, :delivery_status, :string, limit: 30, default: nil

    # 争议表增加字段
    add_column :credit_disputes, :deadline_at, :datetime
    add_column :credit_disputes, :resolution, :string, limit: 500, default: ""
    add_column :credit_disputes, :compensation_amount, :decimal, precision: 20, scale: 2, default: 0
    add_column :credit_disputes, :product_order_id, :integer
    add_index :credit_disputes, :deadline_at
  end
end
