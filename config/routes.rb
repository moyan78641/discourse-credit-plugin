# frozen_string_literal: true

DiscourseCredit::Engine.routes.draw do
  # 钱包
  get  "/wallet"          => "wallet#show"
  get  "/balance"         => "wallet#balance"
  get  "/orders"          => "wallet#orders"
  get  "/order/:id"       => "wallet#order_detail"
  get  "/has-pay-key"     => "wallet#has_pay_key"
  put  "/pay-key"         => "wallet#update_pay_key"

  # 打赏
  post "/tip"             => "tip#create"
  get  "/tip/post/:post_id" => "tip#post_tips"

  # 红包（话题内嵌入）
  post "/redenvelope/create"    => "red_envelope#create"
  post "/redenvelope/claim"     => "red_envelope#claim"
  post "/redenvelope/bind-post" => "red_envelope#bind_post"
  get  "/redenvelope/:id"       => "red_envelope#show"

  # 商户（简化：直接管理商品）
  get    "/merchant/products"              => "product#my_products"
  post   "/merchant/products"              => "product#create"
  put    "/merchant/products/:id"          => "product#update"
  delete "/merchant/products/:id"          => "product#destroy"
  post   "/merchant/products/:id/card-keys" => "product#add_card_keys"
  get    "/merchant/products/:id/card-keys" => "product#card_keys"
  put    "/merchant/card-keys/:id"         => "product#update_card_key"
  delete "/merchant/card-keys/:id"         => "product#delete_card_key"
  get    "/merchant/orders"                => "product#seller_orders"
  put    "/merchant/orders/:id/delivery"   => "product#update_delivery"
  put    "/merchant/dispute/:id/resolve"   => "product#resolve_dispute"

  # 商品公开页
  get  "/product/:id"     => "product#show"
  post "/product/:id/buy" => "product#buy"

  # 买家订单 & 争议
  get  "/my-orders"        => "product#buyer_orders"
  post "/product/dispute"  => "product#create_dispute"

  # 管理后台
  get  "/admin/configs"       => "admin#configs"
  put  "/admin/configs"       => "admin#update_config"
  post "/admin/configs/init"  => "admin#init_configs"
  get  "/admin/users"         => "admin#users"
  put  "/admin/users/admin"   => "admin#set_admin"
  put  "/admin/users/balance" => "admin#set_balance"
  get  "/admin/stats"         => "admin#stats"
  get  "/admin/pay-configs"   => "admin#pay_configs"
  put  "/admin/pay-configs"   => "admin#update_pay_config"
end

Discourse::Application.routes.draw do
  mount ::DiscourseCredit::Engine, at: "/credit"
end
