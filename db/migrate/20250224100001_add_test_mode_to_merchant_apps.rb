# frozen_string_literal: true

class AddTestModeToMerchantApps < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_merchant_apps, :test_mode, :boolean, default: false
  end
end
