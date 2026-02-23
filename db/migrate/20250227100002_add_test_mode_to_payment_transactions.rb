# frozen_string_literal: true

class AddTestModeToPaymentTransactions < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_payment_transactions, :is_test, :boolean, default: false, null: false
  end
end
