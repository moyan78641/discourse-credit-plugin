# frozen_string_literal: true

class AddPostIdToOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_orders, :post_id, :integer
    add_index :credit_orders, :post_id
  end
end
