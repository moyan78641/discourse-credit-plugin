# frozen_string_literal: true

class AddPaymentGatewayFields < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_merchant_apps, :token, :string, limit: 128
    add_column :credit_merchant_apps, :callback_url, :string, limit: 500, default: ""
    add_index :credit_merchant_apps, :token, unique: true

    # 支付交易表（外部支付网关用）
    create_table :credit_payment_transactions do |t|
      t.string :transaction_id, limit: 64, null: false
      t.integer :merchant_app_id, null: false
      t.string :external_reference, limit: 128, null: false
      t.string :description, limit: 500, default: ""
      t.decimal :amount, precision: 20, scale: 2, null: false
      t.decimal :platform_fee, precision: 20, scale: 2, default: 0
      t.decimal :merchant_points, precision: 20, scale: 2, default: 0
      t.string :status, limit: 20, default: "pending"
      t.integer :payer_user_id
      t.integer :credit_order_id
      t.datetime :paid_at
      t.datetime :expires_at
      t.string :error_message, limit: 500
      t.timestamps
    end

    add_index :credit_payment_transactions, :transaction_id, unique: true
    add_index :credit_payment_transactions, :merchant_app_id
    add_index :credit_payment_transactions, :external_reference
    add_index :credit_payment_transactions, :status
  end
end
