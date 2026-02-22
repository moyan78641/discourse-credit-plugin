# frozen_string_literal: true

class CreateCreditTables < ActiveRecord::Migration[7.0]
  def change
    # Wallet — extends Discourse user with credit fields
    create_table :credit_wallets do |t|
      t.integer :user_id, null: false
      t.string :sign_key, limit: 64, null: false
      t.string :pay_key, limit: 200, default: ""
      t.decimal :available_balance, precision: 20, scale: 2, default: 0, null: false
      t.decimal :total_receive, precision: 20, scale: 2, default: 0, null: false
      t.decimal :total_payment, precision: 20, scale: 2, default: 0, null: false
      t.decimal :total_transfer, precision: 20, scale: 2, default: 0, null: false
      t.decimal :total_community, precision: 20, scale: 2, default: 0, null: false
      t.decimal :community_balance, precision: 20, scale: 2, default: 0, null: false
      t.integer :initial_leaderboard_score, default: 0, null: false
      t.integer :pay_score, default: 0, null: false
      t.boolean :is_admin, default: false
      t.timestamps
    end

    add_index :credit_wallets, :user_id, unique: true

    # Orders
    create_table :credit_orders do |t|
      t.string :order_name, limit: 100, null: false
      t.string :merchant_order_no, limit: 64
      t.string :client_id, limit: 64
      t.integer :payer_user_id, default: 0, null: false
      t.integer :payee_user_id, default: 0, null: false
      t.decimal :amount, precision: 20, scale: 2, null: false
      t.string :status, limit: 20, null: false, default: "pending"
      t.string :order_type, limit: 30, null: false
      t.string :remark, limit: 500, default: ""
      t.string :payment_type, limit: 20, default: ""
      t.datetime :trade_time
      t.datetime :expires_at
      t.timestamps
    end

    add_index :credit_orders, :payer_user_id
    add_index :credit_orders, :payee_user_id
    add_index :credit_orders, :status
    add_index :credit_orders, :order_type
    add_index :credit_orders, :client_id
    add_index :credit_orders, :merchant_order_no

    # Red envelopes
    create_table :credit_red_envelopes do |t|
      t.integer :sender_id, null: false
      t.string :envelope_type, limit: 20, null: false
      t.decimal :total_amount, precision: 20, scale: 2, null: false
      t.decimal :remaining_amount, precision: 20, scale: 2, null: false
      t.integer :total_count, null: false
      t.integer :remaining_count, null: false
      t.string :message, limit: 100, default: ""
      t.string :status, limit: 20, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :credit_red_envelopes, :sender_id
    add_index :credit_red_envelopes, :status
    add_index :credit_red_envelopes, :expires_at

    # Red envelope claims
    create_table :credit_red_envelope_claims do |t|
      t.integer :red_envelope_id, null: false
      t.integer :user_id, null: false
      t.decimal :amount, precision: 20, scale: 2, null: false
      t.timestamps
    end

    add_index :credit_red_envelope_claims, :red_envelope_id
    add_index :credit_red_envelope_claims, :user_id
    add_index :credit_red_envelope_claims, %i[red_envelope_id user_id], unique: true, name: "idx_claim_envelope_user"

    # Merchant apps
    create_table :credit_merchant_apps do |t|
      t.integer :user_id, null: false
      t.string :app_name, limit: 100, null: false
      t.string :client_id, limit: 64, null: false
      t.string :client_secret, limit: 128, null: false
      t.string :redirect_uri, limit: 500, default: ""
      t.string :notify_url, limit: 500, default: ""
      t.string :logo_url, limit: 500, default: ""
      t.string :description, limit: 500, default: ""
      t.boolean :is_active, default: true
      t.timestamps
    end

    add_index :credit_merchant_apps, :user_id
    add_index :credit_merchant_apps, :client_id, unique: true

    # Products
    create_table :credit_products do |t|
      t.integer :merchant_app_id, null: false
      t.string :name, limit: 100, null: false
      t.string :description, limit: 500, default: ""
      t.string :logo_url, limit: 500, default: ""
      t.decimal :price, precision: 20, scale: 2, null: false
      t.integer :stock, default: -1
      t.integer :limit_per_user, default: 0
      t.integer :sold_count, default: 0
      t.string :status, limit: 20, default: "active"
      t.timestamps
    end

    add_index :credit_products, :merchant_app_id
    add_index :credit_products, :status

    # Disputes
    create_table :credit_disputes do |t|
      t.integer :order_id, null: false
      t.integer :initiator_user_id, null: false
      t.string :reason, limit: 500, null: false
      t.string :status, limit: 20, default: "disputing"
      t.integer :handler_user_id
      t.timestamps
    end

    add_index :credit_disputes, :order_id, unique: true
    add_index :credit_disputes, :initiator_user_id
    add_index :credit_disputes, :status

    # System configs
    create_table :credit_system_configs, id: false do |t|
      t.string :key, limit: 64, null: false, primary_key: true
      t.string :value, limit: 500, null: false
      t.string :description, limit: 255, default: ""
      t.timestamps
    end

    # Pay level configs
    create_table :credit_pay_configs do |t|
      t.integer :level, null: false
      t.integer :min_score, null: false, default: 0
      t.integer :max_score
      t.integer :daily_limit
      t.decimal :fee_rate, precision: 5, scale: 4, default: 0
      t.decimal :score_rate, precision: 5, scale: 4, default: 0
      t.timestamps
    end

    add_index :credit_pay_configs, :level, unique: true
  end
end
