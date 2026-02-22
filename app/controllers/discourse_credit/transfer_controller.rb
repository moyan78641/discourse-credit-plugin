# frozen_string_literal: true

module ::DiscourseCredit
  class TransferController < BaseController
    # POST /credit/transfer.json
    def create
      wallet = current_wallet!
      return unless verify_pay_key!(params[:pay_key])

      to_username = params[:to_username].to_s.strip
      amount = params[:amount].to_d rescue 0
      remark = params[:remark].to_s[0..99]

      return render json: { error: "金额无效" }, status: 400 if amount <= 0
      return render json: { error: "不能转账给自己" }, status: 400 if to_username == current_user.username

      recipient_user = User.find_by(username: to_username)
      return render json: { error: "收款人不存在" }, status: 400 unless recipient_user&.active

      recipient_wallet = CreditWallet.find_by(user_id: recipient_user.id)
      return render json: { error: "收款人未开通钱包" }, status: 400 unless recipient_wallet

      ActiveRecord::Base.transaction do
        wallet.reload
        raise "余额不足" if wallet.available_balance < amount

        # Deduct payer
        CreditWallet.where(id: wallet.id).update_all(
          "available_balance = available_balance - #{amount}, " \
          "total_transfer = total_transfer + #{amount}, " \
          "total_payment = total_payment + #{amount}",
        )

        # Add to recipient
        CreditWallet.where(id: recipient_wallet.id).update_all(
          "available_balance = available_balance + #{amount}, " \
          "total_receive = total_receive + #{amount}",
        )

        # Payer order
        CreditOrder.create!(
          order_name: "转账给 #{recipient_user.username}",
          payer_user_id: current_user.id,
          payee_user_id: recipient_user.id,
          amount: amount,
          status: "success",
          order_type: "transfer",
          remark: remark,
          trade_time: Time.current,
          expires_at: Time.current,
        )

        # Recipient order
        CreditOrder.create!(
          order_name: "收到 #{current_user.username} 的转账",
          payer_user_id: 0,
          payee_user_id: recipient_user.id,
          amount: amount,
          status: "success",
          order_type: "receive",
          remark: remark,
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      render json: { ok: true }
    rescue => e
      render json: { error: e.message.include?("余额不足") ? "余额不足" : "转账失败" }, status: 400
    end

    # GET /credit/search-user.json?keyword=xxx
    def search_user
      keyword = params[:keyword].to_s.strip
      return render json: { error: "请输入搜索关键词" }, status: 400 if keyword.blank?

      safe_keyword = ActiveRecord::Base.sanitize_sql_like(keyword)
      users = User.where("username ILIKE :q OR name ILIKE :q", q: "%#{safe_keyword}%")
                  .where(active: true)
                  .limit(10)
                  .select(:id, :username, :name)

      render json: {
        users: users.map { |u| { id: u.id, username: u.username, name: u.name } },
      }
    end
  end
end
