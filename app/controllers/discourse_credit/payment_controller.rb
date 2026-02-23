# frozen_string_literal: true

module ::DiscourseCredit
  class PaymentController < BaseController
    skip_before_action :verify_authenticity_token, only: [:process_payment, :query]
    skip_before_action :ensure_logged_in, only: [:process_payment, :query, :pay_page]
    before_action :ensure_logged_in, only: [:confirm]

    # POST /credit/payment/pay/:payment_id/process
    # 外部商户发起支付（API 调用，无需登录）
    def process_payment
      app = CreditMerchantApp.active.find_by(client_id: params[:payment_id])
      return render json: { error: "无效的 payment_id" }, status: 404 unless app

      amount = params[:amount].to_i
      description = params[:description].to_s[0..499]
      order_id = params[:order_id].to_s
      signature = params[:signature].to_s

      return render json: { error: "金额必须大于0" }, status: 400 if amount <= 0
      return render json: { error: "缺少 order_id" }, status: 400 if order_id.blank?
      return render json: { error: "缺少 description" }, status: 400 if description.blank?

      # 验证签名
      sign_params = { amount: amount, description: description, order_id: order_id }
      unless Crypto.hmac_verify(app.secret_key, sign_params, signature)
        return render json: { error: "签名验证失败" }, status: 401
      end

      # 检查 order_id 幂等
      existing = CreditPaymentTransaction.find_by(merchant_app_id: app.id, external_reference: order_id)
      if existing
        if existing.status == "pending" && !existing.expired?
          return render json: {
            payment_url: "#{Discourse.base_url}/credit/payment/pay/#{existing.transaction_id}",
            transaction_id: existing.transaction_id,
            status: existing.status,
            amount: existing.amount.to_i,
          }
        else
          return render json: { error: "该 order_id 已存在且状态为 #{existing.status}" }, status: 409
        end
      end

      transaction_id = Crypto.generate_transaction_id

      # 计算手续费
      fee_rate = CreditSystemConfig.get_f("merchant_fee_rate")
      platform_fee = (amount * fee_rate).round(2)
      merchant_points = (amount - platform_fee).round(2)

      txn = CreditPaymentTransaction.create!(
        transaction_id: transaction_id,
        merchant_app_id: app.id,
        external_reference: order_id,
        description: description,
        amount: amount,
        platform_fee: platform_fee,
        merchant_points: merchant_points,
        status: "pending",
        expires_at: Time.current + 30.minutes,
      )

      render json: {
        payment_url: "#{Discourse.base_url}/credit/payment/pay/#{transaction_id}",
        transaction_id: transaction_id,
        status: "pending",
        amount: amount,
      }
    end

    # GET /credit/payment/pay/:transaction_id — 支付页面（用户浏览器访问）
    def pay_page
      @txn = CreditPaymentTransaction.find_by(transaction_id: params[:transaction_id])
      return render json: { error: "交易不存在" }, status: 404 unless @txn

      app = @txn.merchant_app

      render json: {
        transaction_id: @txn.transaction_id,
        app_name: app.app_name,
        description: @txn.description,
        amount: @txn.amount.to_i,
        platform_fee: @txn.platform_fee.to_i,
        status: @txn.status,
        expired: @txn.expired?,
        expires_at: @txn.expires_at&.iso8601,
      }
    end

    # POST /credit/payment/confirm/:transaction_id — 用户确认支付
    def confirm
      txn = CreditPaymentTransaction.find_by(transaction_id: params[:transaction_id])
      return render json: { error: "交易不存在" }, status: 404 unless txn
      return render json: { error: "交易已过期" }, status: 400 if txn.expired?
      return render json: { error: "交易状态异常: #{txn.status}" }, status: 400 unless txn.completable?

      return unless verify_pay_key!(params[:pay_key])

      wallet = current_wallet!
      app = txn.merchant_app
      amount = txn.amount

      # 防止自付（用户不能给自己的应用付款）
      if current_user.id == app.user_id
        return render json: { error: "不能给自己的应用付款" }, status: 400
      end

      if wallet.available_balance < amount
        return render json: { error: "余额不足" }, status: 400
      end

      merchant_wallet = CreditWallet.find_by(user_id: app.user_id)
      return render json: { error: "商户钱包异常" }, status: 400 unless merchant_wallet

      success = false

      ActiveRecord::Base.transaction do
        # 扣买家（原子操作，防并发）
        rows = CreditWallet.where(id: wallet.id).where("available_balance >= ?", amount).update_all(
          ["available_balance = available_balance - ?, total_payment = total_payment + ?", amount, amount],
        )
        raise ActiveRecord::Rollback if rows == 0

        # 商户到账（扣除手续费）
        CreditWallet.where(id: merchant_wallet.id).update_all(
          ["available_balance = available_balance + ?, total_receive = total_receive + ?", txn.merchant_points, txn.merchant_points],
        )

        fee_rate = amount > 0 ? (txn.platform_fee / amount).to_f.round(4) : 0

        order = CreditOrder.create!(
          order_name: "外部支付: #{txn.description}",
          payer_user_id: current_user.id,
          payee_user_id: app.user_id,
          amount: amount,
          fee_rate: fee_rate,
          fee_amount: txn.platform_fee,
          actual_amount: txn.merchant_points,
          status: "success",
          order_type: "product",
          remark: "外部订单##{txn.external_reference} via #{app.app_name}",
          trade_time: Time.current,
        )

        txn.update!(
          status: "completed",
          payer_user_id: current_user.id,
          credit_order_id: order.id,
          paid_at: Time.current,
        )

        accumulate_pay_score!(wallet, amount)

        success = true
      end

      unless success
        return render json: { error: "余额不足或并发冲突，请重试" }, status: 400
      end

      # 构建回调 URL
      callback_url = build_callback_url(txn, app)

      render json: {
        success: true,
        transaction_id: txn.transaction_id,
        callback_url: callback_url,
      }
    end

    # POST /credit/payment/query/:payment_id — 商户查询交易状态
    def query
      app = CreditMerchantApp.active.find_by(client_id: params[:payment_id])
      return render json: { error: "无效的 payment_id" }, status: 404 unless app

      transaction_id = params[:transaction_id].to_s
      signature = params[:signature].to_s

      sign_params = { transaction_id: transaction_id }
      unless Crypto.hmac_verify(app.secret_key, sign_params, signature)
        return render json: { error: "签名验证失败" }, status: 401
      end

      txn = CreditPaymentTransaction.find_by(transaction_id: transaction_id, merchant_app_id: app.id)
      return render json: { error: "交易不存在" }, status: 404 unless txn

      render json: {
        transaction_id: txn.transaction_id,
        status: txn.status,
        amount: txn.amount.to_i,
        platform_fee: txn.platform_fee.to_i,
        merchant_points: txn.merchant_points.to_i,
        description: txn.description,
        external_reference: txn.external_reference,
        created_at: txn.created_at&.iso8601,
        updated_at: txn.updated_at&.iso8601,
        paid_at: txn.paid_at&.iso8601,
        expires_at: txn.expires_at&.iso8601,
        expired: txn.expired?,
        error_message: txn.error_message,
      }
    end

    private

    def build_callback_url(txn, app)
      return nil if app.callback_url.blank?

      cb_params = {
        transaction_id: txn.transaction_id,
        external_reference: txn.external_reference,
        amount: txn.amount.to_i,
        platform_fee: txn.platform_fee.to_i,
        merchant_points: txn.merchant_points.to_i,
        status: "completed",
        paid_at: txn.paid_at.iso8601,
      }

      signature = Crypto.hmac_sign(app.secret_key, cb_params)
      cb_params[:signature] = signature

      uri = URI.parse(app.callback_url)
      uri.query = URI.encode_www_form(cb_params)
      uri.to_s
    end
  end
end
