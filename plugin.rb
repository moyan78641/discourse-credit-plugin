# frozen_string_literal: true

# name: discourse-credit-plugin
# about: Sparkloc community credit system - wallet, transfer, red envelope, merchant, disputes
# version: 0.1.0
# authors: Sparkloc
# url: https://sparkloc.com

module ::DiscourseCredit
  PLUGIN_NAME = "discourse-credit-plugin"
end

require_relative "lib/discourse_credit/engine"

enabled_site_setting :credit_enabled

register_asset "stylesheets/common/credit.scss"

after_initialize do
  register_svg_icon "wallet"
  register_svg_icon "right-left"
  register_svg_icon "gift"
  register_svg_icon "chart-line"
  register_svg_icon "store"
  register_svg_icon "key"
  register_svg_icon "gears"
  register_svg_icon "gavel"
  register_svg_icon "cart-shopping"
  register_svg_icon "arrow-left"
  register_svg_icon "plus"
  register_svg_icon "magnifying-glass"
  register_svg_icon "check"
  register_svg_icon "xmark"
  register_svg_icon "pen-to-square"
  register_svg_icon "lock"
  # Load models
  plugin_root = File.dirname(__FILE__)
  %w[
    credit_wallet
    credit_order
    credit_red_envelope
    credit_red_envelope_claim
    credit_merchant_app
    credit_product
    credit_dispute
    credit_system_config
    credit_pay_config
  ].each { |m| require File.join(plugin_root, "app", "models", m) }

  # Load lib
  require File.join(plugin_root, "lib", "discourse_credit", "crypto")

  # Load scheduled jobs
  %w[
    sync_credit_scores
    expire_credit_orders
    refund_expired_red_envelopes
    auto_refund_disputes
  ].each { |j| require File.join(plugin_root, "app", "jobs", "scheduled", j) }

  # Load regular jobs
  %w[
    credit_merchant_notify
  ].each { |j| require File.join(plugin_root, "app", "jobs", "regular", j) }
end
