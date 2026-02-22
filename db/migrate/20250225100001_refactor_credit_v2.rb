# frozen_string_literal: true

class RefactorCreditV2 < ActiveRecord::Migration[7.0]
  def change
    # 订单表增加费率相关字段和订单号
    add_column :credit_orders, :order_no, :string, limit: 32
    add_column :credit_orders, :fee_rate, :decimal, precision: 5, scale: 4, default: 0
    add_column :credit_orders, :fee_amount, :decimal, precision: 20, scale: 2, default: 0
    add_column :credit_orders, :actual_amount, :decimal, precision: 20, scale: 2, default: 0
    add_index :credit_orders, :order_no, unique: true

    # 红包增加话题关联和领取模式
    add_column :credit_red_envelopes, :topic_id, :integer
    add_column :credit_red_envelopes, :post_id, :integer
    add_column :credit_red_envelopes, :require_reply, :boolean, default: false
    add_index :credit_red_envelopes, :topic_id
    add_index :credit_red_envelopes, :post_id

    # 商品增加卡密自动发货
    add_column :credit_products, :auto_delivery, :boolean, default: false
    add_column :credit_products, :delivery_message, :string, limit: 1000, default: ""

    # 卡密表
    create_table :credit_card_keys do |t|
      t.integer :product_id, null: false
      t.string :card_key, limit: 500, null: false
      t.string :status, limit: 20, default: "available"
      t.integer :buyer_user_id
      t.integer :order_id
      t.timestamps
    end

    add_index :credit_card_keys, :product_id
    add_index :credit_card_keys, :status
    add_index :credit_card_keys, :buyer_user_id

    # 简化商户：去掉 app 概念，商品直接挂用户
    add_column :credit_products, :user_id, :integer
    add_index :credit_products, :user_id
  end
end
