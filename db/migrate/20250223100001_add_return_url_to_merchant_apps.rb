# frozen_string_literal: true

class AddReturnUrlToMerchantApps < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_merchant_apps, :return_url, :string, limit: 500, default: ""
  end
end
