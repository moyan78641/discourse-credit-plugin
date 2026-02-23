# frozen_string_literal: true

module ::DiscourseCredit
  class BaseController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_logged_in

    private

    def current_wallet
      @current_wallet ||= CreditWallet.find_by(user_id: current_user.id)
    end

    def current_wallet!
      wallet = current_wallet
      raise Discourse::NotFound unless wallet
      wallet
    end

    def ensure_wallet
      return render json: { error: "请先初始化钱包" }, status: 400 unless current_wallet
    end

    def ensure_pay_key
      wallet = current_wallet!
      unless wallet.has_pay_key?
        return render json: { error: "请先设置支付密码" }, status: 400
      end
    end

    def verify_pay_key!(pay_key_input)
      wallet = current_wallet!
      unless Crypto.verify_pay_key(wallet.sign_key, wallet.pay_key, pay_key_input)
        render json: { error: "支付密码错误" }, status: 400
        return false
      end
      true
    end

    def ensure_credit_admin
      wallet = current_wallet
      unless current_user.admin? || wallet&.is_admin
        render json: { error: "需要管理员权限" }, status: 403
        return false
      end
      true
    end

    def config_get(key)
      CreditSystemConfig.get(key)
    end

    def config_get_i(key)
      CreditSystemConfig.get_i(key)
    end

    def config_get_f(key)
      CreditSystemConfig.get_f(key)
    end

    # 获取用户实际费率：优先等级费率，fallback 到全局配置
    # 注意：等级费率为 0 也是有效值（VIP免手续费），只有未配置时才 fallback
    def resolve_fee_rate(wallet, config_key)
      pay_config = wallet.pay_config
      if pay_config && pay_config.fee_rate.present?
        pay_config.fee_rate.to_f
      else
        config_get_f(config_key)
      end
    end

    # 交易后累积 pay_score
    def accumulate_pay_score!(wallet, spent_amount)
      rate = config_get_f("pay_score_rate")
      return if rate <= 0 || spent_amount <= 0
      score_delta = (spent_amount.to_d * rate).round(0).to_i
      return if score_delta <= 0
      CreditWallet.where(id: wallet.id).update_all(
        ["pay_score = pay_score + ?", score_delta],
      )
    end
  end
end
