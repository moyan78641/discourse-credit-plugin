# frozen_string_literal: true

module ::DiscourseCredit
  class ProductController < BaseController
    skip_before_action :ensure_logged_in, only: [:show]

    # GET /credit/merchant/:merchant_id/products.json
    def index
      app = CreditMerchantApp.find_by(id: params[:merchant_id], user_id: current_user.id)
      return render json: { error: "商户不存在" }, status: 404 unless app

      products = CreditProduct.where(merchant_app_id: app.id).order(created_at: :desc)
      render json: { products: products.as_json }
    end

    # POST /credit/merchant/:merchant_id/products.json
    def create
      app = CreditMerchantApp.find_by(id: params[:merchant_id], user_id: current_user.id)
      return render json: { error: "商户不存在" }, status: 404 unless app

      price = params[:price].to_d rescue 0
      return render json: { error: "请填写商品名称和价格" }, status: 400 if params[:name].blank?
      return render json: { error: "价格无效" }, status: 400 if price <= 0

      stock = params[:stock].present? ? params[:stock].to_i : -1

      product = CreditProduct.create!(
        merchant_app_id: app.id,
        name: params[:name],
        description: params[:description] || "",
        logo_url: params[:logo_url] || "",
        price: price,
        stock: stock,
        limit_per_user: params[:limit_per_user].to_i,
        status: "active",
      )

      render json: { product: product.as_json }
    end

    # PUT /credit/merchant/:merchant_id/products/:product_id.json
    def update
      app = CreditMerchantApp.find_by(id: params[:merchant_id], user_id: current_user.id)
      return render json: { error: "商户不存在" }, status: 404 unless app

      product = CreditProduct.find_by(id: params[:product_id], merchant_app_id: app.id)
      return render json: { error: "商品不存在" }, status: 404 unless product

      updates = {}
      updates[:name] = params[:name] if params[:name].present?
      updates[:description] = params[:description] if params.key?(:description)
      updates[:logo_url] = params[:logo_url] if params.key?(:logo_url)
      if params[:price].present?
        p = params[:price].to_d rescue 0
        updates[:price] = p if p > 0
      end
      updates[:stock] = params[:stock].to_i if params.key?(:stock)
      updates[:limit_per_user] = params[:limit_per_user].to_i if params.key?(:limit_per_user)
      updates[:status] = params[:status] if %w[active inactive].include?(params[:status])

      product.update!(updates) if updates.any?
      render json: { product: product.reload.as_json }
    end

    # DELETE /credit/merchant/:merchant_id/products/:product_id.json
    def destroy
      app = CreditMerchantApp.find_by(id: params[:merchant_id], user_id: current_user.id)
      return render json: { error: "商户不存在" }, status: 404 unless app

      product = CreditProduct.find_by(id: params[:product_id], merchant_app_id: app.id)
      return render json: { error: "商品不存在" }, status: 404 unless product

      product.destroy!
      render json: { ok: true }
    end

    # GET /credit/product/:id.json — public product detail
    def show
      product = CreditProduct.find_by(id: params[:id])
      return render json: { error: "商品不存在" }, status: 404 unless product

      merchant = CreditMerchantApp.find_by(id: product.merchant_app_id)

      render json: {
        product: {
          id: product.id,
          merchant_app_id: product.merchant_app_id,
          name: product.name,
          description: product.description,
          logo_url: product.logo_url,
          price: product.price.to_f,
          stock: product.stock,
          limit_per_user: product.limit_per_user,
          sold_count: product.sold_count,
          status: product.status,
          merchant_name: merchant&.app_name,
        },
      }
    end

    # POST /credit/product/:id/buy.json
    def buy
      wallet = current_wallet!
      return unless verify_pay_key!(params[:pay_key])

      product = nil
      fee_rate = config_get_f("merchant_fee_rate")

      ActiveRecord::Base.transaction do
        product = CreditProduct.lock.find_by(id: params[:id], status: "active")
        raise "商品不存在或已下架" unless product
        raise "商品已售罄" if product.stock == 0

        # Check limit per user
        if product.limit_per_user > 0
          bought = CreditOrder.where(payer_user_id: current_user.id, order_type: "payment")
                              .where("remark LIKE ?", "%product:#{product.id}%")
                              .where(status: "success").count
          raise "该商品限购 #{product.limit_per_user} 件" if bought >= product.limit_per_user
        end

        merchant = CreditMerchantApp.find_by(id: product.merchant_app_id)
        raise "商户不存在" unless merchant
        raise "不能购买自己的商品" if merchant.user_id == current_user.id

        wallet.reload
        raise "余额不足" if wallet.available_balance < product.price

        fee = (product.price * fee_rate).round(2)
        merchant_amount = product.price - fee

        # Deduct buyer
        CreditWallet.where(id: wallet.id).update_all(
          "available_balance = available_balance - #{product.price}, " \
          "total_payment = total_payment + #{product.price}",
        )

        # Credit merchant
        merchant_wallet = CreditWallet.find_by(user_id: merchant.user_id)
        if merchant_wallet
          CreditWallet.where(id: merchant_wallet.id).update_all(
            "available_balance = available_balance + #{merchant_amount}, " \
            "total_receive = total_receive + #{merchant_amount}",
          )
        end

        # Update stock & sold
        updates = { sold_count: product.sold_count + 1 }
        updates[:stock] = product.stock - 1 if product.stock > 0
        product.update!(updates)

        # Buyer order
        CreditOrder.create!(
          order_name: "购买商品: #{product.name}",
          payer_user_id: current_user.id,
          payee_user_id: merchant.user_id,
          amount: product.price,
          status: "success",
          order_type: "payment",
          remark: "product:#{product.id}, 手续费:#{fee}",
          trade_time: Time.current,
          expires_at: Time.current,
        )

        # Merchant income order
        buyer_name = current_user.username
        CreditOrder.create!(
          order_name: "#{buyer_name} 购买了: #{product.name}",
          payer_user_id: 0,
          payee_user_id: merchant.user_id,
          amount: merchant_amount,
          status: "success",
          order_type: "receive",
          remark: "product:#{product.id}, 手续费:#{fee}",
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      render json: { ok: true }
    rescue => e
      msg = %w[余额不足 商品已售罄 限购 不能购买 商品不存在 商户不存在].find { |k| e.message.include?(k) }
      render json: { error: msg || "购买失败" }, status: 400
    end
  end
end
