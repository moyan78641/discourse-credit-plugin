# frozen_string_literal: true

module ::DiscourseCredit
  class ProductController < BaseController
    skip_before_action :ensure_logged_in, only: [:show]

    # GET /credit/merchant/products.json — 我的商品列表
    def my_products
      products = CreditProduct.where(user_id: current_user.id).order(created_at: :desc)
      render json: {
        products: products.map { |p|
          {
            id: p.id, name: p.name, description: p.description, price: p.price.to_f,
            stock: p.stock, sold_count: p.sold_count, status: p.status,
            auto_delivery: p.auto_delivery, delivery_message: p.delivery_message,
            card_key_count: p.auto_delivery ? p.card_keys.available.count : nil,
          }
        },
      }
    end

    # POST /credit/merchant/products.json — 创建商品
    def create
      product = CreditProduct.new(
        user_id: current_user.id,
        merchant_app_id: 0,
        name: params[:name],
        description: params[:description] || "",
        price: params[:price],
        stock: params[:stock] || -1,
        limit_per_user: params[:limit_per_user] || 0,
        auto_delivery: params[:auto_delivery] == "true" || params[:auto_delivery] == true,
        delivery_message: params[:delivery_message] || "",
        status: "active",
      )

      if product.save
        render json: { product: { id: product.id, name: product.name } }
      else
        render json: { error: product.errors.full_messages.join(", ") }, status: 400
      end
    end

    # PUT /credit/merchant/products/:id.json — 更新商品
    def update
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product

      allowed = {}
      allowed[:name] = params[:name] if params[:name].present?
      allowed[:description] = params[:description] if params.key?(:description)
      allowed[:price] = params[:price] if params[:price].present?
      allowed[:stock] = params[:stock] if params.key?(:stock)
      allowed[:limit_per_user] = params[:limit_per_user] if params.key?(:limit_per_user)
      allowed[:status] = params[:status] if params[:status].present?
      allowed[:auto_delivery] = (params[:auto_delivery] == "true" || params[:auto_delivery] == true) if params.key?(:auto_delivery)
      allowed[:delivery_message] = params[:delivery_message] if params.key?(:delivery_message)

      product.update!(allowed)
      render json: { success: true }
    end

    # DELETE /credit/merchant/products/:id.json — 删除商品
    def destroy
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product
      product.destroy!
      render json: { success: true }
    end

    # POST /credit/merchant/products/:id/card-keys.json — 批量添加卡密
    def add_card_keys
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product

      keys = params[:keys] # 数组或换行分隔的字符串
      if keys.is_a?(String)
        keys = keys.split(/[\r\n]+/).map(&:strip).reject(&:blank?)
      end

      return render json: { error: "请提供卡密" }, status: 400 if keys.blank?

      count = 0
      keys.each do |k|
        CreditCardKey.create!(product_id: product.id, card_key: k, status: "available")
        count += 1
      end

      render json: { success: true, added: count, total_available: product.card_keys.available.count }
    end

    # GET /credit/merchant/products/:id/card-keys.json — 查看卡密列表
    def card_keys
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product

      keys = product.card_keys.order(created_at: :desc).map do |k|
        { id: k.id, card_key: k.card_key, status: k.status, buyer_user_id: k.buyer_user_id }
      end

      render json: { keys: keys }
    end

    # GET /credit/product/:id.json — 商品详情（公开）
    def show
      product = CreditProduct.find_by(id: params[:id])
      return render json: { error: "商品不存在" }, status: 404 unless product

      owner = User.find_by(id: product.user_id)
      render json: {
        id: product.id, name: product.name, description: product.description,
        price: product.price.to_f, stock: product.stock, sold_count: product.sold_count,
        status: product.status, auto_delivery: product.auto_delivery,
        owner_username: owner&.username,
        in_stock: product.in_stock?,
      }
    end

    # POST /credit/product/:id/buy.json — 购买商品
    def buy
      product = CreditProduct.find_by(id: params[:id])
      return render json: { error: "商品不存在" }, status: 404 unless product
      return render json: { error: "商品已下架" }, status: 400 unless product.status == "active"
      return render json: { error: "库存不足" }, status: 400 unless product.in_stock?

      return unless verify_pay_key!(params[:pay_key])

      wallet = current_wallet!
      amount = product.price
      fee_rate = config_get_f("merchant_fee_rate")
      fee_amount = (amount * fee_rate).round(2)
      actual_amount = (amount - fee_amount).round(2)

      if wallet.available_balance < amount
        return render json: { error: "余额不足" }, status: 400
      end

      if product.user_id == current_user.id
        return render json: { error: "不能购买自己的商品" }, status: 400
      end

      # 限购检查
      if product.limit_per_user > 0
        bought = CreditOrder.where(payer_user_id: current_user.id, order_type: "product", remark: "商品##{product.id}").successful.count
        if bought >= product.limit_per_user
          return render json: { error: "已达到限购数量" }, status: 400
        end
      end

      seller_wallet = CreditWallet.find_by(user_id: product.user_id)
      return render json: { error: "卖家钱包异常" }, status: 400 unless seller_wallet

      card_key_content = nil
      order = nil

      ActiveRecord::Base.transaction do
        wallet.update!(available_balance: wallet.available_balance - amount, total_payment: wallet.total_payment + amount)
        seller_wallet.update!(available_balance: seller_wallet.available_balance + actual_amount, total_receive: seller_wallet.total_receive + actual_amount)

        # 更新库存
        if product.stock > 0
          product.update!(stock: product.stock - 1, sold_count: product.sold_count + 1)
        else
          product.update!(sold_count: product.sold_count + 1)
        end

        order = CreditOrder.create!(
          order_name: "购买: #{product.name}",
          payer_user_id: current_user.id,
          payee_user_id: product.user_id,
          amount: amount,
          fee_rate: fee_rate,
          fee_amount: fee_amount,
          actual_amount: actual_amount,
          status: "success",
          order_type: "product",
          remark: "商品##{product.id}",
          trade_time: Time.current,
        )

        # 自动发卡密
        if product.auto_delivery
          card = product.card_keys.available.first
          if card
            card.update!(status: "sold", buyer_user_id: current_user.id, order_id: order.id)
            card_key_content = card.card_key

            # 站内信发送卡密
            msg_body = "您购买的商品【#{product.name}】已自动发货。\n\n"
            msg_body += "#{product.delivery_message}\n\n" if product.delivery_message.present?
            msg_body += "卡密: `#{card_key_content}`\n\n"
            msg_body += "订单号: #{order.order_no}"

            PostCreator.create!(
              Discourse.system_user,
              title: "商品发货通知: #{product.name}",
              raw: msg_body,
              archetype: Archetype.private_message,
              target_usernames: [current_user.username],
              skip_validations: true,
            )
          end
        end
      end

      render json: {
        success: true,
        order_no: order.order_no,
        auto_delivery: product.auto_delivery,
        has_card_key: card_key_content.present?,
      }
    end
  end
end
