# frozen_string_literal: true

# name: discourse-credit-plugin
# about: Sparkloc community credit system - wallet, tipping, red envelope, merchant
# version: 2.0.0
# authors: Sparkloc
# url: https://sparkloc.com

module ::DiscourseCredit
  PLUGIN_NAME = "discourse-credit-plugin"
end

require_relative "lib/discourse_credit/engine"

enabled_site_setting :credit_enabled

register_asset "stylesheets/common/credit.scss"

after_initialize do
  # SVG icons
  %w[
    wallet gift store cart-shopping arrow-left plus key gears
    bolt-lightning envelope heart hand-holding-heart right-left
    chart-line magnifying-glass check xmark pen-to-square lock
    circle-plus receipt file-lines
  ].each { |i| register_svg_icon i }

  # Load models
  plugin_root = File.dirname(__FILE__)
  %w[
    credit_wallet
    credit_order
    credit_red_envelope
    credit_red_envelope_claim
    credit_product
    credit_card_key
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
    resolve_expired_disputes
  ].each { |j| require File.join(plugin_root, "app", "jobs", "scheduled", j) }

  # Ember shell 路由 (仅 HTML，不拦截 .json API 请求)
  Discourse::Application.routes.prepend do
    constraints(->(req) { !req.path.end_with?(".json") }) do
      get "/credit" => "list#latest"
      get "/credit/merchant" => "list#latest"
      get "/credit/product/:id" => "list#latest"
      get "/credit/my-orders" => "list#latest"
      get "/credit/admin" => "list#latest"
    end
  end

  # Markdown 扩展：渲染红包卡片 [red-envelope id=xxx]
  on(:before_post_process_cooked) do |doc, post|
    # 处理红包标记
  end
end
