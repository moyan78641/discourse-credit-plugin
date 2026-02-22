# frozen_string_literal: true

module ::DiscourseCredit
  class TipController < BaseController
    before_action :ensure_wallet, only: [:create]
    before_action :ensure_pay_key, only: [:create]
    skip_before_action :ensure_logged_in, only: [:post_tips]

    # POST /credit/tip
    # params: target_user_id, amount, pay_key, tip_type (topic/comment/profile), post_id (optional)
    def create
      target_user_id = params[:target_user_id].to_i
      amount = params[:amount].to_f
      pay_key_input = params[:pay_key]
      tip_type = params[:tip_type] || "profile"
      post_id = params[:post_id]

      if target_user_id == current_user.id
        return render json: { error: "不能给自己打赏" }, status: 400
      end

      target_user = User.find_by(id: target_user_id)
      return render json: { error: "目标用户不存在" }, status: 404 unless target_user

      min_amount = config_get_f("tip_min_amount")
      max_amount = config_get_f("tip_max_amount")
      if amount < min_amount || amount > max_amount
        return render json: { error: "打赏金额需在 #{min_amount} ~ #{max_amount} 之间" }, status: 400
      end

      return unless verify_pay_key!(pay_key_input)

      wallet = current_wallet!
      fee_rate = config_get_f("tip_fee_rate")
      fee_amount = (amount * fee_rate).round(2)
      total_deduct = amount + fee_amount  # 手续费额外扣除

      if wallet.available_balance < total_deduct
        return render json: { error: "余额不足（含手续费 #{fee_amount}）" }, status: 400
      end

      target_wallet = CreditWallet.find_by(user_id: target_user_id)
      unless target_wallet
        return render json: { error: "对方未开通钱包" }, status: 400
      end

      # 构建备注
      remark = case tip_type
               when "topic" then "话题打赏"
               when "comment" then "评论打赏"
               else "个人主页打赏"
               end
      remark += " (帖子##{post_id})" if post_id.present?

      ActiveRecord::Base.transaction do
        wallet.update!(available_balance: wallet.available_balance - total_deduct, total_payment: wallet.total_payment + total_deduct)
        target_wallet.update!(available_balance: target_wallet.available_balance + amount, total_receive: target_wallet.total_receive + amount)

        order = CreditOrder.create!(
          order_name: "打赏 @#{target_user.username}",
          payer_user_id: current_user.id,
          payee_user_id: target_user_id,
          amount: amount,
          fee_rate: fee_rate,
          fee_amount: fee_amount,
          actual_amount: amount,
          status: "success",
          order_type: "tip",
          remark: remark,
          post_id: post_id.present? ? post_id.to_i : nil,
          trade_time: Time.current,
        )

        render json: { success: true, order_no: order.order_no, amount: amount, fee_amount: fee_amount, actual_amount: amount, total_deduct: total_deduct }
      end
    end

    # GET /credit/tip/post/:post_id.json — 获取帖子的打赏记录
    def post_tips
      post_id = params[:post_id].to_i
      tips = CreditOrder.where(order_type: "tip", post_id: post_id, status: "success").order(created_at: :desc)

      user_ids = tips.map(&:payer_user_id).uniq
      users = User.where(id: user_ids).index_by(&:id)

      total = tips.sum(:amount).to_f

      render json: {
        total_amount: total,
        count: tips.count,
        tips: tips.map { |t|
          u = users[t.payer_user_id]
          {
            username: u&.username,
            avatar_template: u&.avatar_template,
            amount: t.amount.to_f,
            created_at: t.created_at&.iso8601,
          }
        },
      }
    end
  end
end
