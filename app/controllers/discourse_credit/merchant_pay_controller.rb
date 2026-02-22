# frozen_string_literal: true

require "digest/md5"
require "net/http"
require "uri"

module ::DiscourseCredit
  class MerchantPayController < BaseController
    skip_before_action :ensure_logged_in, only: [:create_order, :query_order, :refund_order]
    skip_before_action :verify_authenticity_token, only: [:create_order, :query_order, :refund_order, :confirm]

    # EPay签名字段白名单
    EPAY_SIGN_FIELDS = %w[pid type out_trade_no notify_url return_url name money device].freeze

    # GET/POST /credit-pay/submit.php — 易支付兼容创建订单
    def create_order
      client_id = params[:pid].to_s
      merchant_order_no = params[:out_trade_no].to_s
      notify_url = params[:notify_url].to_s
      return_url = params[:return_url].to_s
      name = params[:name].to_s
      money = params[:money].to_s
      sign = params[:sign].to_s

      if client_id.blank? || merchant_order_no.blank? || name.blank? || money.blank? || sign.blank?
        return render json: { code: -1, msg: "参数不完整" }
      end

      app = CreditMerchantApp.find_by(client_id: client_id, is_active: true)
      return render json: { code: -1, msg: "商户不存在" } unless app

      # Verify MD5 sign (only use EPay fields)
      epay_params = {}
      EPAY_SIGN_FIELDS.each { |k| epay_params[k] = params[k].to_s if params[k].present? }
      epay_params["sign"] = sign

      unless verify_sign(epay_params, app.client_secret)
        return render json: { code: -1, msg: "签名错误" }
      end

      amount = money.to_d rescue 0
      return render json: { code: -1, msg: "金额无效" } if amount <= 0

      expire_minutes = config_get_i("merchant_order_expire_minutes")
      expire_minutes = 30 if expire_minutes <= 0

      order = CreditOrder.create!(
        order_name: name,
        client_id: client_id,
        merchant_order_no: merchant_order_no,
        payee_user_id: app.user_id,
        payer_user_id: 0,
        amount: amount,
        status: "pending",
        order_type: "payment",
        payment_type: params[:type] || "",
        expires_at: Time.current + expire_minutes.minutes,
      )

      # Store notify/return URLs in PluginStore (no Redis dependency)
      PluginStore.set("credit_notify", "order_#{order.id}", {
        "notify_url" => notify_url.presence,
        "return_url" => return_url.presence,
      })

      # Redirect to cashier page
      frontend_url = SiteSetting.credit_frontend_url.presence || Discourse.base_url
      pay_url = "#{frontend_url}/credit/pay?order_id=#{order.id}"
      redirect_to pay_url, allow_other_host: true
    end

    # GET /credit-api.php — 易支付兼容查询订单
    def query_order
      client_id = params[:pid].to_s
      client_secret = params[:key].to_s
      merchant_order_no = params[:out_trade_no].to_s

      if client_id.blank? || client_secret.blank? || merchant_order_no.blank?
        return render json: { code: -1, msg: "参数不完整" }
      end

      app = CreditMerchantApp.find_by(client_id: client_id, client_secret: client_secret)
      return render json: { code: -1, msg: "商户验证失败" } unless app

      order = CreditOrder.find_by(client_id: client_id, merchant_order_no: merchant_order_no)
      return render json: { code: -1, msg: "订单不存在" } unless order

      status = order.status == "success" ? 1 : 0

      render json: {
        code: 1,
        msg: "查询成功",
        trade_no: order.id.to_s,
        out_trade_no: order.merchant_order_no,
        type: order.payment_type,
        pid: order.client_id,
        addtime: order.created_at.strftime("%Y-%m-%d %H:%M:%S"),
        endtime: (order.trade_time || order.created_at).strftime("%Y-%m-%d %H:%M:%S"),
        name: order.order_name,
        money: format("%.2f", order.amount),
        status: status,
      }
    end

    # POST /credit-api.php — 易支付兼容退款
    def refund_order
      client_id = params[:pid].to_s
      client_secret = params[:key].to_s
      trade_no = params[:trade_no].to_i
      money = params[:money].to_s

      if client_id.blank? || client_secret.blank? || trade_no <= 0 || money.blank?
        return render json: { code: -1, msg: "参数不完整" }
      end

      app = CreditMerchantApp.find_by(client_id: client_id, client_secret: client_secret)
      return render json: { code: -1, msg: "商户验证失败" } unless app

      refund_amount = money.to_d rescue 0
      return render json: { code: -1, msg: "金额无效" } if refund_amount <= 0

      ActiveRecord::Base.transaction do
        order = CreditOrder.lock.find_by(
          id: trade_no,
          client_id: client_id,
          status: "success",
          amount: refund_amount,
        )
        unless order && %w[payment online].include?(order.order_type)
          raise "订单不存在或不可退款"
        end

        # Refund to payer
        if order.payer_user_id > 0
          CreditWallet.where(user_id: order.payer_user_id).update_all(
            "available_balance = available_balance + #{order.amount}, " \
            "total_payment = total_payment - #{order.amount}",
          )
        end

        # Deduct from merchant
        CreditWallet.where(user_id: order.payee_user_id).update_all(
          "available_balance = available_balance - #{order.amount}, " \
          "total_receive = total_receive - #{order.amount}",
        )

        order.update!(status: "refund")
      end

      render json: { code: 1, msg: "退款成功" }
    rescue => e
      render json: { code: -1, msg: e.message }
    end

    # GET /credit/pay/order.json?order_id=xxx — get pending order info for cashier
    def get_order
      order = CreditOrder.find_by(id: params[:order_id], status: "pending")
      return render json: { error: "订单不存在或已处理" }, status: 404 unless order
      return render json: { error: "订单已过期" }, status: 400 if order.expires_at < Time.current

      app = CreditMerchantApp.find_by(client_id: order.client_id)

      render json: {
        order: {
          id: order.id,
          name: order.order_name,
          amount: order.amount.to_f,
          expires_at: order.expires_at,
        },
        merchant: { name: app&.app_name },
      }
    end

    # POST /credit/pay/confirm.json — user confirms payment
    def confirm
      order_id = params[:order_id].to_i
      wallet = current_wallet!
      return unless verify_pay_key!(params[:pay_key])

      return_url = nil
      fee_rate = config_get_f("merchant_fee_rate")

      ActiveRecord::Base.transaction do
        order = CreditOrder.lock.find_by(id: order_id, status: "pending")
        raise "订单不存在或已处理" unless order
        raise "订单已过期" if order.expires_at < Time.current

        wallet.reload
        raise "余额不足" if wallet.available_balance < order.amount

        fee = (order.amount * fee_rate).round(2)
        merchant_amount = order.amount - fee

        # Deduct payer
        CreditWallet.where(id: wallet.id).update_all(
          "available_balance = available_balance - #{order.amount}, " \
          "total_payment = total_payment + #{order.amount}",
        )

        # Credit merchant
        merchant_wallet = CreditWallet.find_by(user_id: order.payee_user_id)
        if merchant_wallet
          CreditWallet.where(id: merchant_wallet.id).update_all(
            "available_balance = available_balance + #{merchant_amount}, " \
            "total_receive = total_receive + #{merchant_amount}",
          )
        end

        order.update!(
          status: "success",
          payer_user_id: current_user.id,
          trade_time: Time.current,
          remark: "手续费: #{format('%.2f', fee)}",
        )

        # Get return URL
        stored = PluginStore.get("credit_notify", "order_#{order.id}")
        return_url = stored&.dig("return_url")

        # Async notify via Discourse Jobs
        Jobs.enqueue_in(2.seconds, :credit_merchant_notify, order_id: order.id)
      end

      render json: { ok: true, return_url: return_url }
    rescue => e
      msg = %w[余额不足 订单不存在 订单已过期 订单已处理].find { |k| e.message.include?(k) }
      render json: { error: msg || "支付失败" }, status: 400
    end

    private

    def verify_sign(epay_params, secret)
      sign_val = epay_params.delete("sign") || epay_params.delete(:sign)
      filtered = epay_params.reject { |k, v| %w[sign sign_type].include?(k.to_s) || v.to_s.empty? }
      sorted_keys = filtered.keys.map(&:to_s).sort
      str = sorted_keys.map { |k| "#{k}=#{filtered[k]}" }.join("&") + secret
      expected = Digest::MD5.hexdigest(str)
      ActiveSupport::SecurityUtils.secure_compare(expected, sign_val.to_s.downcase)
    end

    def generate_sign(params_hash, secret)
      filtered = params_hash.reject { |k, _| %w[sign sign_type].include?(k.to_s) }
      sorted_keys = filtered.keys.map(&:to_s).sort
      str = sorted_keys.map { |k| "#{k}=#{filtered[k]}" }.join("&") + secret
      Digest::MD5.hexdigest(str)
    end
  end
end
