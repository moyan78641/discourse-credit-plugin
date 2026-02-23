# frozen_string_literal: true

module ::DiscourseCredit
  class ProductController < BaseController
    skip_before_action :ensure_logged_in, only: [:show]

    # GET /credit/merchant/products.json
    def my_products
      products = CreditProduct.where(user_id: current_user.id).order(created_at: :desc)
      render json: {
        products: products.map { |p|
          display_stock = p.auto_delivery ? p.card_keys.available.count : p.stock
          {
            id: p.id, name: p.name, description: p.description, price: p.price.to_f,
            stock: display_stock, sold_count: p.sold_count, status: p.status,
            auto_delivery: p.auto_delivery, delivery_message: p.delivery_message,
            card_key_count: p.auto_delivery ? p.card_keys.available.count : nil,
          }
        },
      }
    end

    # POST /credit/merchant/products.json
    def create
      is_auto = params[:auto_delivery] == "true" || params[:auto_delivery] == true
      product = CreditProduct.new(
        user_id: current_user.id, merchant_app_id: 0,
        name: params[:name], description: params[:description] || "",
        price: params[:price], stock: is_auto ? 0 : (params[:stock] || -1),
        limit_per_user: params[:limit_per_user] || 0,
        auto_delivery: is_auto, delivery_message: params[:delivery_message] || "",
        status: "active",
      )
      if product.save
        render json: { product: { id: product.id, name: product.name } }
      else
        render json: { error: product.errors.full_messages.join(", ") }, status: 400
      end
    end

    # PUT /credit/merchant/products/:id.json
    def update
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product
      allowed = {}
      %i[name description price stock limit_per_user status delivery_message].each do |f|
        allowed[f] = params[f] if params.key?(f)
      end
      if params.key?(:auto_delivery)
        allowed[:auto_delivery] = (params[:auto_delivery] == "true" || params[:auto_delivery] == true)
      end
      product.update!(allowed)
      render json: { success: true }
    end

    # DELETE /credit/merchant/products/:id.json
    def destroy
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product
      product.destroy!
      render json: { success: true }
    end

    # POST /credit/merchant/products/:id/card-keys.json — 批量添加
    def add_card_keys
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product
      keys = params[:keys]
      keys = keys.split(/[\r\n]+/).map(&:strip).reject(&:blank?) if keys.is_a?(String)
      return render json: { error: "请提供卡密" }, status: 400 if keys.blank?
      count = 0
      keys.each do |k|
        CreditCardKey.create!(product_id: product.id, card_key: k, status: "available")
        count += 1
      end
      render json: { success: true, added: count, total_available: product.card_keys.available.count }
    end

    # GET /credit/merchant/products/:id/card-keys.json
    def card_keys
      product = CreditProduct.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "商品不存在" }, status: 404 unless product
      keys = product.card_keys.order(created_at: :desc).map do |k|
        { id: k.id, card_key: k.card_key, status: k.status, buyer_user_id: k.buyer_user_id }
      end
      render json: { keys: keys }
    end

    # PUT /credit/merchant/card-keys/:id.json — 编辑卡密
    def update_card_key
      key = CreditCardKey.find_by(id: params[:id])
      return render json: { error: "卡密不存在" }, status: 404 unless key
      product = CreditProduct.find_by(id: key.product_id, user_id: current_user.id)
      return render json: { error: "无权操作" }, status: 403 unless product
      return render json: { error: "已售出的卡密不可修改" }, status: 400 if key.status == "sold"
      key.update!(card_key: params[:card_key]) if params[:card_key].present?
      render json: { success: true }
    end

    # DELETE /credit/merchant/card-keys/:id.json — 删除卡密
    def delete_card_key
      key = CreditCardKey.find_by(id: params[:id])
      return render json: { error: "卡密不存在" }, status: 404 unless key
      product = CreditProduct.find_by(id: key.product_id, user_id: current_user.id)
      return render json: { error: "无权操作" }, status: 403 unless product
      return render json: { error: "已售出的卡密不可删除" }, status: 400 if key.status == "sold"
      key.destroy!
      render json: { success: true }
    end

    # GET /credit/merchant/orders.json — 卖家订单列表（待发货等）
    def seller_orders
      orders = CreditOrder.where(payee_user_id: current_user.id, order_type: "product")
                          .where.not(delivery_status: nil)
                          .order(created_at: :desc)
      render json: {
        orders: orders.map { |o|
          buyer = User.find_by(id: o.payer_user_id)
          dispute = CreditDispute.find_by(order_id: o.id)
          {
            id: o.id, order_no: o.order_no, order_name: o.order_name,
            amount: o.amount.to_f, delivery_status: o.delivery_status,
            buyer_username: buyer&.username, created_at: o.created_at&.iso8601,
            has_dispute: dispute.present?,
            dispute_id: dispute&.id,
            dispute_status: dispute&.status,
            dispute_reason: dispute&.reason,
            dispute_deadline: dispute&.deadline_at&.iso8601,
          }
        },
      }
    end

    # PUT /credit/merchant/orders/:id/delivery.json — 更新发货状态
    def update_delivery
      order = CreditOrder.find_by(id: params[:id], payee_user_id: current_user.id, order_type: "product")
      return render json: { error: "订单不存在" }, status: 404 unless order
      return render json: { error: "该订单无需发货" }, status: 400 if order.delivery_status.nil?

      new_status = params[:delivery_status]
      valid = %w[processing delivered refunded]
      return render json: { error: "无效状态" }, status: 400 unless valid.include?(new_status)

      if new_status == "refunded"
        # 卖家主动退款
        perform_refund!(order, "卖家主动退款")
      else
        order.update!(delivery_status: new_status)
        # 发货确认时，卖家到账（扣除手续费）
        if new_status == "delivered"
          seller_wallet = CreditWallet.find_by(user_id: current_user.id)
          if seller_wallet
            actual_amount = order.actual_amount
            seller_wallet.update!(
              available_balance: seller_wallet.available_balance + actual_amount,
              total_receive: seller_wallet.total_receive + actual_amount,
            )
          end

          buyer = User.find_by(id: order.payer_user_id)
          if buyer
            PostCreator.create!(
              Discourse.system_user,
              title: "商品发货通知",
              raw: "您购买的商品【#{order.order_name.sub('购买: ', '')}】已发货。\n\n订单号: #{order.order_no}",
              archetype: Archetype.private_message,
              target_usernames: [buyer.username],
              skip_validations: true,
            )
          end
        end
      end
      render json: { success: true }
    end

    # GET /credit/product/:id.json — 商品详情（公开）
    def show
      product = CreditProduct.find_by(id: params[:id])
      return render json: { error: "商品不存在" }, status: 404 unless product
      owner = User.find_by(id: product.user_id)
      display_stock = product.auto_delivery ? product.card_keys.available.count : product.stock
      render json: {
        id: product.id, name: product.name, description: product.description,
        price: product.price.to_f, stock: display_stock, sold_count: product.sold_count,
        status: product.status, auto_delivery: product.auto_delivery,
        owner_username: owner&.username, in_stock: product.in_stock?,
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
      # 费率：优先用户等级费率，fallback 到全局 merchant_fee_rate
      fee_rate = resolve_fee_rate(wallet, "merchant_fee_rate")
      fee_amount = (amount * fee_rate).round(2)
      actual_amount = (amount - fee_amount).round(2)

      return render json: { error: "余额不足" }, status: 400 if wallet.available_balance < amount
      return render json: { error: "不能购买自己的商品" }, status: 400 if product.user_id == current_user.id

      if product.limit_per_user > 0
        bought = CreditOrder.where(payer_user_id: current_user.id, order_type: "product", remark: "商品##{product.id}").successful.count
        return render json: { error: "已达到限购数量" }, status: 400 if bought >= product.limit_per_user
      end

      seller_wallet = CreditWallet.find_by(user_id: product.user_id)
      return render json: { error: "卖家钱包异常" }, status: 400 unless seller_wallet

      card_key_content = nil
      order = nil

      ActiveRecord::Base.transaction do
        # 买家扣款
        wallet.update!(
          available_balance: wallet.available_balance - amount,
          total_payment: wallet.total_payment + amount,
        )

        if product.auto_delivery
          # 卡密自动发货：卖家立即到账（扣除手续费）
          seller_wallet.update!(
            available_balance: seller_wallet.available_balance + actual_amount,
            total_receive: seller_wallet.total_receive + actual_amount,
          )
        end
        # 非卡密商品：卖家暂不到账，发货确认后再到账

        if product.stock > 0
          product.update!(stock: product.stock - 1, sold_count: product.sold_count + 1)
        else
          product.update!(sold_count: product.sold_count + 1)
        end

        # 非卡密商品设置 delivery_status
        ds = product.auto_delivery ? nil : "pending_delivery"

        order = CreditOrder.create!(
          order_name: "购买: #{product.name}",
          payer_user_id: current_user.id, payee_user_id: product.user_id,
          amount: amount, fee_rate: fee_rate, fee_amount: fee_amount,
          actual_amount: actual_amount, status: "success", order_type: "product",
          remark: "商品##{product.id}", trade_time: Time.current,
          delivery_status: ds,
        )

        if product.auto_delivery
          card = product.card_keys.available.first
          if card
            card.update!(status: "sold", buyer_user_id: current_user.id, order_id: order.id)
            card_key_content = card.card_key
            msg_body = "您购买的商品【#{product.name}】已自动发货。\n\n"
            msg_body += "#{product.delivery_message}\n\n" if product.delivery_message.present?
            msg_body += "卡密: `#{card_key_content}`\n\n订单号: #{order.order_no}"
            PostCreator.create!(
              Discourse.system_user, title: "商品发货通知: #{product.name}",
              raw: msg_body, archetype: Archetype.private_message,
              target_usernames: [current_user.username], skip_validations: true,
            )
          end
        end

        # 累积买家的 pay_score
        accumulate_pay_score!(wallet, amount)
      end

      render json: {
        success: true, order_no: order.order_no,
        auto_delivery: product.auto_delivery,
        has_card_key: card_key_content.present?,
        delivery_status: order.delivery_status,
      }
    end

    # POST /credit/product/dispute.json — 买家发起争议
    def create_dispute
      order = CreditOrder.find_by(id: params[:order_id], payer_user_id: current_user.id, order_type: "product")
      return render json: { error: "订单不存在" }, status: 404 unless order
      return render json: { error: "该订单已有争议" }, status: 400 if CreditDispute.exists?(order_id: order.id)
      return render json: { error: "请填写争议原因" }, status: 400 if params[:reason].blank?

      # 只有非卡密的待发货/充值中订单可以争议
      if order.delivery_status.nil?
        return render json: { error: "自动发货订单不支持争议" }, status: 400
      end

      dispute = CreditDispute.create!(
        order_id: order.id,
        product_order_id: order.id,
        initiator_user_id: current_user.id,
        reason: params[:reason],
        status: "disputing",
        deadline_at: Time.current + 48.hours,
      )

      # 通知卖家
      seller = User.find_by(id: order.payee_user_id)
      if seller
        PostCreator.create!(
          Discourse.system_user,
          title: "商品争议通知",
          raw: "买家 @#{current_user.username} 对订单【#{order.order_name}】发起了争议。\n\n原因: #{params[:reason]}\n\n请在48小时内处理，否则将自动退款并扣除补偿积分。\n\n订单号: #{order.order_no}",
          archetype: Archetype.private_message,
          target_usernames: [seller.username],
          skip_validations: true,
        )
      end

      render json: { success: true, dispute_id: dispute.id, deadline_at: dispute.deadline_at.iso8601 }
    end

    # PUT /credit/merchant/dispute/:id/resolve.json — 卖家处理争议
    def resolve_dispute
      dispute = CreditDispute.find_by(id: params[:id], status: "disputing")
      return render json: { error: "争议不存在或已处理" }, status: 404 unless dispute

      order = CreditOrder.find_by(id: dispute.order_id)
      return render json: { error: "订单不存在" }, status: 404 unless order
      return render json: { error: "无权操作" }, status: 403 unless order.payee_user_id == current_user.id

      action = params[:action_type] # "refund" or "reject"
      case action
      when "refund"
        perform_refund!(order, "卖家同意退款 (争议##{dispute.id})")
        dispute.update!(status: "resolved", resolution: "卖家同意退款", handler_user_id: current_user.id)
      when "reject"
        dispute.update!(status: "rejected", resolution: params[:resolution] || "卖家拒绝", handler_user_id: current_user.id)
        # 通知买家
        buyer = User.find_by(id: order.payer_user_id)
        if buyer
          PostCreator.create!(
            Discourse.system_user,
            title: "争议处理结果",
            raw: "卖家已处理您的争议（订单 #{order.order_no}）。\n\n处理结果: 拒绝退款\n说明: #{params[:resolution] || '无'}",
            archetype: Archetype.private_message,
            target_usernames: [buyer.username],
            skip_validations: true,
          )
        end
      else
        return render json: { error: "无效操作" }, status: 400
      end

      render json: { success: true }
    end

    # GET /credit/my-orders.json — 买家的商品订单（含发货状态和争议）
    def buyer_orders
      orders = CreditOrder.where(payer_user_id: current_user.id, order_type: "product")
                          .order(created_at: :desc).limit(50)
      render json: {
        orders: orders.map { |o|
          seller = User.find_by(id: o.payee_user_id)
          dispute = CreditDispute.find_by(order_id: o.id)
          {
            id: o.id, order_no: o.order_no, order_name: o.order_name,
            amount: o.amount.to_f, delivery_status: o.delivery_status,
            status: o.status,
            seller_username: seller&.username, created_at: o.created_at&.iso8601,
            has_dispute: dispute.present?,
            dispute_status: dispute&.status,
            dispute_id: dispute&.id,
          }
        },
      }
    end

    private

    def perform_refund!(order, reason)
      ActiveRecord::Base.transaction do
        buyer_wallet = CreditWallet.find_by(user_id: order.payer_user_id)
        seller_wallet = CreditWallet.find_by(user_id: order.payee_user_id)

        # 退还买家全额（商品原价）
        if buyer_wallet
          buyer_wallet.update!(
            available_balance: buyer_wallet.available_balance + order.amount,
            total_payment: [buyer_wallet.total_payment - order.amount, 0].max,
          )
        end

        # 只有卖家已到账的情况才扣回（已发货 or 卡密自动发货）
        seller_received = order.delivery_status.nil? || order.delivery_status == "delivered"
        if seller_wallet && seller_received
          seller_wallet.update!(
            available_balance: seller_wallet.available_balance - order.actual_amount,
            total_receive: [seller_wallet.total_receive - order.actual_amount, 0].max,
          )
        end

        order.update!(delivery_status: "refunded", status: "refunded")

        CreditOrder.create!(
          order_name: "退款: #{order.order_name}",
          payer_user_id: order.payee_user_id, payee_user_id: order.payer_user_id,
          amount: order.amount, status: "success", order_type: "product_refund",
          remark: reason, trade_time: Time.current,
        )
      end
    end
  end
end
