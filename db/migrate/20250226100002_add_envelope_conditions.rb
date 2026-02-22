# frozen_string_literal: true

class AddEnvelopeConditions < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_red_envelopes, :require_like, :boolean, default: false
    add_column :credit_red_envelopes, :require_keyword, :string, limit: 100, default: ""
  end
end
