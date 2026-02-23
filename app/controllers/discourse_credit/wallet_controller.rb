# frozen_string_literal: true

module ::DiscourseCredit
  class WalletController < BaseController
    # GET /credit/wallet.json — 获取或自动创建钱包
    def show
      wallet = find_or_create_wallet!
      config = wallet.pay_config

      render json: {
        user_id: wallet.user_id,
        username: current_user.username,
        avatar_url: current_user.avatar_template.gsub("{size}", "120"),
        available_balance: wallet.available_balance.to_f,
        total_receive: wallet.total_receive.to_f,
        total_payment: wallet.total_payment.to_f,
        community_balance: wallet.community_balance.to_f,
        initial_leaderboard_score: wallet.initial_leaderboard_score,
        current_leaderboard_score: fetch_gamification_score(current_user.id),
        pay_score: wallet.pay_score,
        pay_level: wallet.pay_level,
        pay_level_name: wallet.pay_level_name,
        is_admin: wallet.is_admin || current_user.admin?,
        has_pay_key: wallet.has_pay_key?,
        daily_limit: config&.daily_limit,
        fee_rate: resolve_fee_rate(wallet, "tip_fee_rate"),
        created_at: wallet.created_at,
      }
    end

    # GET /credit/balance.json
    def balance
      wallet = current_wallet!
      render json: {
        available_balance: wallet.available_balance.to_f,
        total_receive: wallet.total_receive.to_f,
        total_payment: wallet.total_payment.to_f,
        community_balance: wallet.community_balance.to_f,
      }
    end

    # GET /credit/orders.json — 交易记录列表
    def orders
      wallet = current_wallet!
      page = (params[:page] || 1).to_i
      page_size = params[:page_size].present? ? [[params[:page_size].to_i, 1].max, 50].min : 20
      order_type = params[:type] || "all"

      scope = CreditOrder.where("payer_user_id = :uid OR payee_user_id = :uid", uid: current_user.id)

      case order_type
      when "income"
        scope = CreditOrder.income_for(current_user.id)
      when "expense"
        scope = CreditOrder.expense_for(current_user.id)
      when "tip"
        scope = scope.where(order_type: "tip")
      when "red_envelope"
        scope = scope.where(order_type: %w[red_envelope_send red_envelope_receive red_envelope_refund])
      when "product"
        scope = scope.where(order_type: "product")
      when "community"
        scope = scope.where(order_type: "community")
      end

      total = scope.count
      records = scope.order(created_at: :desc).offset((page - 1) * page_size).limit(page_size)

      user_ids = records.flat_map { |o| [o.payer_user_id, o.payee_user_id] }.uniq.reject(&:zero?)
      user_map = User.where(id: user_ids).index_by(&:id)

      list = records.map do |o|
        payer = user_map[o.payer_user_id]
        payee = user_map[o.payee_user_id]
        is_income = o.payee_user_id == current_user.id && o.payer_user_id != current_user.id

        # 显示金额：收入方看 actual_amount，支出方看 amount + fee
        display_amount = if is_income
          o.actual_amount.to_f
        else
          (o.amount + (o.fee_amount || 0)).to_f
        end

        {
          id: o.id,
          order_no: o.order_no,
          order_name: o.order_name,
          amount: o.amount.to_f,
          display_amount: display_amount,
          fee_rate: o.fee_rate.to_f,
          fee_amount: o.fee_amount.to_f,
          actual_amount: o.actual_amount.to_f,
          status: o.status,
          type: o.order_type,
          is_income: is_income,
          remark: o.remark,
          payer_username: payer&.username || (o.payer_user_id == 0 ? "系统" : "未知"),
          payee_username: payee&.username || (o.payee_user_id == 0 ? "系统" : "未知"),
          created_at: o.created_at,
          trade_time: o.trade_time,
        }
      end

      render json: { total: total, page: page, page_size: page_size, list: list }
    end

    # GET /credit/order/:id.json — 订单详情
    def order_detail
      order = CreditOrder.find_by(id: params[:id])
      return render json: { error: "订单不存在" }, status: 404 unless order

      unless order.payer_user_id == current_user.id || order.payee_user_id == current_user.id || current_user.admin?
        return render json: { error: "无权查看" }, status: 403
      end

      render json: order.as_detail_json(current_user.id)
    end

    # GET /credit/has-pay-key.json
    def has_pay_key
      wallet = current_wallet
      render json: { has_pay_key: wallet&.has_pay_key? || false }
    end

    # PUT /credit/pay-key.json
    def update_pay_key
      wallet = find_or_create_wallet!

      new_key = params[:new_key].to_s
      unless new_key.match?(/\A\d{6}\z/)
        return render json: { error: "支付密码必须是6位数字" }, status: 400
      end

      if wallet.has_pay_key?
        old_key = params[:old_key].to_s
        return render json: { error: "请输入原密码" }, status: 400 if old_key.blank?
        unless Crypto.verify_pay_key(wallet.sign_key, wallet.pay_key, old_key)
          return render json: { error: "原密码错误" }, status: 400
        end
      end

      encrypted = Crypto.encrypt(wallet.sign_key, new_key)
      wallet.update!(pay_key: encrypted)
      render json: { ok: true }
    end

    private

    def find_or_create_wallet!
      wallet = CreditWallet.find_by(user_id: current_user.id)
      return wallet if wallet

      initial_score = fetch_gamification_score(current_user.id)  # 记录当前分数作为基准
      initial_credit = SiteSetting.credit_new_user_balance.to_d

      wallet = CreditWallet.create!(
        user_id: current_user.id,
        sign_key: Crypto.generate_sign_key,
        initial_leaderboard_score: initial_score,
        available_balance: initial_credit,
        total_receive: initial_credit,
        community_balance: 0,
        total_community: 0,
        is_admin: current_user.admin?,
      )

      # 注册奖励订单
      if initial_credit > 0
        CreditOrder.create!(
          order_name: "新用户注册奖励",
          payer_user_id: 0,
          payee_user_id: current_user.id,
          amount: initial_credit,
          fee_rate: 0,
          fee_amount: 0,
          actual_amount: initial_credit,
          status: "success",
          order_type: "community",
          remark: "新用户 #{current_user.username} 注册赠送初始积分",
          trade_time: Time.current,
        )
      end

      # 记录开通信息，方便用户了解基准
      CreditOrder.create!(
        order_name: "开通积分钱包",
        payer_user_id: 0,
        payee_user_id: current_user.id,
        amount: 0,
        status: "success",
        order_type: "community",
        remark: "开通钱包，基准分数: #{initial_score}",
        trade_time: Time.current,
      )

      wallet
    end

    def fetch_gamification_score(user_id)
      result = DB.query_single(
        "SELECT score FROM gamification_score_events_mv WHERE user_id = :uid LIMIT 1",
        uid: user_id,
      )
      result.first || 0
    rescue
      user = User.find_by(id: user_id)
      user&.respond_to?(:gamification_score) ? (user.gamification_score || 0) : 0
    end
  end
end
