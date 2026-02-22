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
  end
end
