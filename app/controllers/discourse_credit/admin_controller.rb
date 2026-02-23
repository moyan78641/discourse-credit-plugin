# frozen_string_literal: true

module ::DiscourseCredit
  class AdminController < BaseController
    before_action :ensure_credit_admin, except: [:my_apps, :create_app, :update_app, :regenerate_token]

    # GET /credit/admin/configs.json
    def configs
      all = CreditSystemConfig.all.order(:key)
      render json: { configs: all.as_json }
    end

    # PUT /credit/admin/configs.json
    def update_config
      key = params[:key].to_s
      value = params[:value].to_s
      return render json: { error: "参数错误" }, status: 400 if key.blank? || value.blank?

      config = CreditSystemConfig.find_or_initialize_by(key: key)
      config.value = value
      config.save!
      render json: { ok: true, config: config.as_json }
    end

    # POST /credit/admin/configs/init.json
    def init_configs
      CreditSystemConfig.seed_defaults!
      CreditPayConfig.seed_defaults!
      render json: { ok: true, message: "初始化完成" }
    end

    # GET /credit/admin/users.json?page=1&page_size=20&search=xxx
    def users
      page = (params[:page] || 1).to_i
      page_size = params[:page_size].present? ? [[params[:page_size].to_i, 1].max, 100].min : 20
      search = params[:search].to_s.strip

      scope = CreditWallet.all
      if search.present?
        safe_search = ActiveRecord::Base.sanitize_sql_like(search)
        user_ids = User.where("username ILIKE :q OR name ILIKE :q", q: "%#{safe_search}%").pluck(:id)
        scope = scope.where(user_id: user_ids)
      end

      total = scope.count
      wallets = scope.order(created_at: :desc).offset((page - 1) * page_size).limit(page_size)

      user_ids = wallets.map(&:user_id)
      user_map = User.where(id: user_ids).index_by(&:id)

      list = wallets.map do |w|
        u = user_map[w.user_id]
        {
          user_id: w.user_id,
          username: u&.username,
          name: u&.name,
          available_balance: w.available_balance.to_f,
          total_receive: w.total_receive.to_f,
          total_payment: w.total_payment.to_f,
          total_transfer: w.total_transfer.to_f,
          community_balance: w.community_balance.to_f,
          pay_score: w.pay_score,
          is_admin: w.is_admin,
          created_at: w.created_at,
        }
      end

      render json: { list: list, total: total, page: page, page_size: page_size }
    end

    # PUT /credit/admin/users/admin.json
    def set_admin
      user_id = params[:user_id].to_i
      is_admin = params[:is_admin] == true || params[:is_admin] == "true"

      wallet = CreditWallet.find_by(user_id: user_id)
      return render json: { error: "用户钱包不存在" }, status: 404 unless wallet

      wallet.update!(is_admin: is_admin)
      render json: { ok: true }
    end

    # PUT /credit/admin/users/balance.json
    def set_balance
      user_id = params[:user_id].to_i
      amount = params[:amount].to_d rescue 0
      remark = params[:remark].to_s

      return render json: { error: "金额格式错误" }, status: 400 if amount == 0

      wallet = CreditWallet.find_by(user_id: user_id)
      return render json: { error: "用户钱包不存在" }, status: 404 unless wallet

      # Pre-check balance before transaction
      if amount < 0 && wallet.available_balance + amount < 0
        return render json: { error: "余额不足" }, status: 400
      end

      ActiveRecord::Base.transaction do
        CreditWallet.where(id: wallet.id).update_all(
          "available_balance = available_balance + #{amount}",
        )

        order_name = remark.present? ? remark : "管理员调整"
        payer_id = amount > 0 ? 0 : user_id
        payee_id = amount > 0 ? user_id : 0

        CreditOrder.create!(
          order_name: order_name,
          payer_user_id: payer_id,
          payee_user_id: payee_id,
          amount: amount.abs,
          status: "success",
          order_type: "distribute",
          remark: "操作人: #{current_user.username}",
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      wallet.reload
      render json: { ok: true, new_balance: wallet.available_balance.to_f }
    end

    # GET /credit/admin/stats.json
    def stats
      user_count = CreditWallet.count
      total_balance = CreditWallet.sum(:available_balance).to_f
      today_orders = CreditOrder.where("created_at >= ?", Time.current.beginning_of_day).count

      render json: {
        user_count: user_count,
        total_balance: total_balance,
        today_orders: today_orders,
      }
    end

    # GET /credit/admin/pay-configs.json
    def pay_configs
      configs = CreditPayConfig.order(:level)
      render json: {
        configs: configs.map { |c|
          {
            level: c.level,
            level_name: CreditPayConfig.level_name(c.level),
            min_score: c.min_score,
            max_score: c.max_score,
            daily_limit: c.daily_limit,
            fee_rate: c.fee_rate&.to_f || 0,
            score_rate: c.score_rate&.to_f || 0,
          }
        },
      }
    end

    # PUT /credit/admin/pay-configs.json
    def update_pay_config
      level = params[:level].to_i
      config = CreditPayConfig.find_by(level: level)
      return render json: { error: "等级不存在，请先初始化配置" }, status: 404 unless config

      updates = {}
      updates[:min_score] = params[:min_score].to_i if params[:min_score].present?
      updates[:max_score] = params[:max_score].present? ? params[:max_score].to_i : nil
      updates[:daily_limit] = params[:daily_limit].present? ? params[:daily_limit].to_i : nil
      updates[:fee_rate] = params[:fee_rate].to_d if params[:fee_rate].present?
      updates[:score_rate] = params[:score_rate].to_d if params[:score_rate].present?

      config.update!(updates) if updates.any?
      render json: { ok: true }
    end

    # === 应用管理（任何已登录用户都可以创建应用） ===

    # GET /credit/apps.json — 我的应用列表
    def my_apps
      apps = CreditMerchantApp.where(user_id: current_user.id).order(created_at: :desc)
      render json: {
        apps: apps.map { |a|
          {
            id: a.id,
            app_name: a.app_name,
            client_id: a.client_id,
            token: a.token,
            callback_url: a.callback_url,
            description: a.description,
            is_active: a.is_active,
            created_at: a.created_at&.iso8601,
          }
        },
      }
    end

    # POST /credit/apps.json — 创建应用
    def create_app
      app_name = params[:app_name].to_s.strip
      return render json: { error: "请填写应用名称" }, status: 400 if app_name.blank?

      app = CreditMerchantApp.create!(
        user_id: current_user.id,
        app_name: app_name,
        client_id: "pay_#{SecureRandom.hex(12)}",
        client_secret: SecureRandom.hex(32),
        callback_url: params[:callback_url].to_s.strip,
        description: params[:description].to_s.strip[0..499],
        is_active: true,
      )

      render json: {
        id: app.id,
        app_name: app.app_name,
        client_id: app.client_id,
        token: app.token,
        callback_url: app.callback_url,
      }
    end

    # PUT /credit/apps/:id.json — 更新应用
    def update_app
      app = CreditMerchantApp.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "应用不存在" }, status: 404 unless app

      updates = {}
      updates[:app_name] = params[:app_name] if params[:app_name].present?
      updates[:callback_url] = params[:callback_url] if params.key?(:callback_url)
      updates[:description] = params[:description] if params.key?(:description)
      updates[:is_active] = (params[:is_active] == "true" || params[:is_active] == true) if params.key?(:is_active)

      app.update!(updates) if updates.any?
      render json: { ok: true }
    end

    # POST /credit/apps/:id/token.json — 重新生成 token
    def regenerate_token
      app = CreditMerchantApp.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "应用不存在" }, status: 404 unless app

      app.generate_token!
      render json: { token: app.token }
    end
  end
end
