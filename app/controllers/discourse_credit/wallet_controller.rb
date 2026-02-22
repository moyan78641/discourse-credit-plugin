# frozen_string_literal: true

module ::DiscourseCredit
  class WalletController < BaseController
    skip_before_action :ensure_logged_in, only: []

    # GET /credit/wallet.json — get or auto-create wallet
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
        total_transfer: wallet.total_transfer.to_f,
        community_balance: wallet.community_balance.to_f,
        pay_score: wallet.pay_score,
        pay_level: wallet.pay_level,
        pay_level_name: wallet.pay_level_name,
        is_admin: wallet.is_admin || current_user.admin?,
        has_pay_key: wallet.has_pay_key?,
        daily_limit: config&.daily_limit,
        fee_rate: config&.fee_rate&.to_f || 0,
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
        total_transfer: wallet.total_transfer.to_f,
        community_balance: wallet.community_balance.to_f,
      }
    end

    # GET /credit/orders.json
    def orders
      wallet = current_wallet!
      page = (params[:page] || 1).to_i
      page_size = params[:page_size].present? ? [[params[:page_size].to_i, 1].max, 50].min : 20
      order_type = params[:type] || "all"

      scope = CreditOrder.where(
        "payer_user_id = :uid OR payee_user_id = :uid", uid: current_user.id,
      )

      case order_type
      when "income"
        scope = CreditOrder.income_for(current_user.id)
      when "expense"
        scope = CreditOrder.expense_for(current_user.id)
      end

      total = scope.count
      records = scope.order(created_at: :desc)
                     .offset((page - 1) * page_size)
                     .limit(page_size)

      # Batch load usernames
      user_ids = records.flat_map { |o| [o.payer_user_id, o.payee_user_id] }.uniq.reject(&:zero?)
      user_map = User.where(id: user_ids).index_by(&:id)

      list = records.map do |o|
        payer = user_map[o.payer_user_id]
        payee = user_map[o.payee_user_id]
        is_income = o.payee_user_id == current_user.id && o.payer_user_id != current_user.id

        {
          id: o.id,
          order_name: o.order_name,
          amount: o.amount.to_f,
          status: o.status,
          type: o.order_type,
          is_income: is_income,
          remark: o.remark,
          payer_username: payer&.username,
          payee_username: payee&.username,
          created_at: o.created_at,
        }
      end

      render json: { total: total, page: page, page_size: page_size, list: list }
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

      # New user — get gamification_score baseline
      initial_score = current_user.respond_to?(:gamification_score) ? (current_user.gamification_score || 0) : 0
      initial_credit = config_get_i("new_user_initial_credit").to_d

      wallet = CreditWallet.create!(
        user_id: current_user.id,
        sign_key: Crypto.generate_sign_key,
        initial_leaderboard_score: initial_score,
        available_balance: initial_credit,
        total_receive: initial_credit,
        is_admin: current_user.admin?,
      )

      # Record initial credit order
      if initial_credit > 0
        CreditOrder.create!(
          order_name: "新用户注册奖励",
          payer_user_id: 0,
          payee_user_id: current_user.id,
          amount: initial_credit,
          status: "success",
          order_type: "community",
          remark: "新用户 #{current_user.username} 注册赠送初始积分",
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      wallet
    end
  end
end
