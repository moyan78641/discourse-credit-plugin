# frozen_string_literal: true

module ::DiscourseCredit
  class MerchantController < BaseController
    # GET /credit/merchant/apps.json
    def apps
      apps = CreditMerchantApp.where(user_id: current_user.id).order(created_at: :desc)
      render json: { apps: apps.as_json }
    end

    # POST /credit/merchant/apps.json
    def create_app
      app_name = (params[:name] || params[:app_name]).to_s.strip
      return render json: { error: "请填写应用名称" }, status: 400 if app_name.blank?

      app = CreditMerchantApp.create!(
        user_id: current_user.id,
        app_name: app_name,
        client_id: Crypto.generate_random_string(32),
        client_secret: Crypto.generate_random_string(48),
        redirect_uri: params[:redirect_uri] || "",
        return_url: params[:return_url] || "",
        notify_url: params[:notify_url] || "",
        description: params[:description] || "",
        is_active: true,
      )

      render json: { app: app.as_json }
    end

    # PUT /credit/merchant/apps/:id.json
    def update_app
      app = CreditMerchantApp.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "应用不存在" }, status: 404 unless app

      updates = {}
      new_name = (params[:name] || params[:app_name]).to_s.strip
      updates[:app_name] = new_name if new_name.present?
      updates[:redirect_uri] = params[:redirect_uri] if params.key?(:redirect_uri)
      updates[:return_url] = params[:return_url] if params.key?(:return_url)
      updates[:notify_url] = params[:notify_url] if params.key?(:notify_url)
      updates[:description] = params[:description] if params.key?(:description)
      updates[:is_active] = params[:is_active] if params.key?(:is_active)
      updates[:test_mode] = params[:test_mode] if params.key?(:test_mode)

      app.update!(updates) if updates.any?
      app.reload
      render json: { app: app.as_json }
    end

    # POST /credit/merchant/apps/:id/reset-secret.json
    def reset_secret
      app = CreditMerchantApp.find_by(id: params[:id], user_id: current_user.id)
      return render json: { error: "应用不存在" }, status: 404 unless app

      app.update!(client_secret: Crypto.generate_random_string(48))
      render json: { app: app.as_json, message: "密钥已重置" }
    end
  end
end
