# frozen_string_literal: true

DiscourseCredit::Engine.routes.draw do
  # User wallet & profile
  get  "/wallet"          => "wallet#show"
  get  "/balance"         => "wallet#balance"
  get  "/orders"          => "wallet#orders"
  get  "/has-pay-key"     => "wallet#has_pay_key"
  put  "/pay-key"         => "wallet#update_pay_key"

  # Transfer
  post "/transfer"        => "transfer#create"
  get  "/search-user"     => "transfer#search_user"

  # Red envelope
  post "/redenvelope/create"  => "red_envelope#create"
  post "/redenvelope/claim"   => "red_envelope#claim"
  get  "/redenvelope/list"    => "red_envelope#list"
  get  "/redenvelope/:id"     => "red_envelope#show"

  # Merchant app management
  get    "/merchant/apps"                => "merchant#apps"
  post   "/merchant/apps"                => "merchant#create_app"
  put    "/merchant/apps/:id"            => "merchant#update_app"
  post   "/merchant/apps/:id/reset-secret" => "merchant#reset_secret"

  # Product management
  get    "/merchant/:merchant_id/products"              => "product#index"
  post   "/merchant/:merchant_id/products"              => "product#create"
  put    "/merchant/:merchant_id/products/:product_id"  => "product#update"
  delete "/merchant/:merchant_id/products/:product_id"  => "product#destroy"

  # Product purchase
  get  "/product/:id"     => "product#show"
  post "/product/:id/buy" => "product#buy"

  # Disputes
  post "/disputes"            => "dispute#list"
  post "/disputes/merchant"   => "dispute#list_merchant"
  post "/dispute"             => "dispute#create"
  post "/dispute/review"      => "dispute#review"
  post "/dispute/close"       => "dispute#close"

  # Dashboard
  get "/dashboard/daily-stats"     => "dashboard#daily_stats"
  get "/dashboard/overview"        => "dashboard#overview"
  get "/dashboard/recent"          => "dashboard#recent"
  get "/dashboard/top-customers"   => "dashboard#top_customers"

  # Admin
  get  "/admin/configs"       => "admin#configs"
  put  "/admin/configs"       => "admin#update_config"
  post "/admin/configs/init"  => "admin#init_configs"
  get  "/admin/users"         => "admin#users"
  put  "/admin/users/admin"   => "admin#set_admin"
  put  "/admin/users/balance" => "admin#set_balance"
  get  "/admin/stats"         => "admin#stats"

  # Merchant payment API (易支付 compatible)
  get  "/pay/order"   => "merchant_pay#get_order"
  post "/pay/confirm" => "merchant_pay#confirm"
end

Discourse::Application.routes.draw do
  mount ::DiscourseCredit::Engine, at: "/credit"
end

# 易支付兼容接口 (top-level)
Discourse::Application.routes.draw do
  scope module: "discourse_credit" do
    match "/credit-pay/submit.php", to: "merchant_pay#create_order", via: [:get, :post]
    get   "/credit-api.php",        to: "merchant_pay#query_order"
    post  "/credit-api.php",        to: "merchant_pay#refund_order"
  end
end

# Top-level Ember page routes — Rails must serve the Ember shell for direct URL access
Discourse::Application.routes.draw do
  get "/credit" => "list#latest"
  get "/credit/transfer" => "list#latest"
  get "/credit/redenvelope" => "list#latest"
  get "/credit/redenvelope/:id" => "list#latest"
  get "/credit/merchant" => "list#latest"
  get "/credit/product/:id" => "list#latest"
  get "/credit/disputes" => "list#latest"
  get "/credit/dashboard" => "list#latest"
  get "/credit/admin" => "list#latest"
  get "/credit/pay" => "list#latest"
end
