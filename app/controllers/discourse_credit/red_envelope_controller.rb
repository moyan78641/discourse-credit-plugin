# frozen_string_literal: true

module ::DiscourseCredit
  class RedEnvelopeController < BaseController
    skip_before_action :ensure_logged_in, only: [:show]

    # POST /credit/redenvelope/create.json
    # 创建话题内红包（从编辑器调用）
    def create
      wallet = current_wallet!
      return unless verify_pay_key!(params[:pay_key])

      amount = params[:amount].to_d rescue 0
      count = params[:count].to_i
      envelope_type = params[:type] == "random" ? "random" : "fixed"
      message = params[:message].to_s[0..49]
      require_reply = params[:require_reply] == "true" || params[:require_reply] == true

      max_amount = config_get_i("red_envelope_max_amount")
      return render json: { error: "金额无效" }, status: 400 if amount <= 0
      return render json: { error: "红包金额不能超过 #{max_amount}" }, status: 400 if amount > max_amount
      return render json: { error: "人数无效" }, status: 400 if count < 1 || count > config_get_i("red_envelope_max_recipients")

      min_total = BigDecimal("0.01") * count
      return render json: { error: "红包金额太小" }, status: 400 if amount < min_total

      fee_rate = config_get_f("red_envelope_fee_rate")
      fee_amount = (amount * fee_rate).round(2)
      total_deduct = amount + fee_amount

      expire_hours = config_get_i("red_envelope_expire_hours")
      expire_hours = 24 if expire_hours <= 0

      envelope = nil

      ActiveRecord::Base.transaction do
        wallet.reload
        raise "余额不足" if wallet.available_balance < total_deduct

        wallet.update!(
          available_balance: wallet.available_balance - total_deduct,
          total_payment: wallet.total_payment + total_deduct,
        )

        envelope = CreditRedEnvelope.create!(
          sender_id: current_user.id,
          envelope_type: envelope_type,
          total_amount: amount,
          remaining_amount: amount,
          total_count: count,
          remaining_count: count,
          message: message,
          status: "active",
          require_reply: require_reply,
          expires_at: Time.current + expire_hours.hours,
        )

        CreditOrder.create!(
          order_name: "发红包 (#{count}个)",
          payer_user_id: current_user.id,
          payee_user_id: 0,
          amount: total_deduct,
          fee_rate: fee_rate,
          fee_amount: fee_amount,
          actual_amount: amount,
          status: "success",
          order_type: "red_envelope_send",
          remark: "#{envelope_type == 'random' ? '拼手气' : '均分'}红包#{message.present? ? ': ' + message : ''}",
          trade_time: Time.current,
        )
      end

      render json: { id: envelope.id, message: "红包创建成功" }
    rescue => e
      render json: { error: e.message.include?("余额不足") ? "余额不足" : "创建红包失败" }, status: 400
    end

    # POST /credit/redenvelope/claim.json
    def claim
      wallet = current_wallet!
      envelope_id = params[:id].to_i

      claim_amount = nil

      ActiveRecord::Base.transaction do
        envelope = CreditRedEnvelope.lock.find_by(id: envelope_id)
        raise "红包不存在" unless envelope
        raise "红包已结束" unless envelope.status == "active"
        raise "红包已过期" if envelope.expires_at < Time.current
        raise "不能领取自己的红包" if envelope.sender_id == current_user.id
        raise "您已领取过该红包" if envelope.claimed_by?(current_user.id)
        raise "红包已被领完" if envelope.exhausted?

        # 检查是否需要回复
        if envelope.require_reply && envelope.topic_id.present?
          has_reply = Post.where(topic_id: envelope.topic_id, user_id: current_user.id)
                         .where("post_number > 1").exists?
          raise "需要先回复该话题才能领取红包" unless has_reply
        end

        if envelope.envelope_type == "fixed"
          claim_amount = (envelope.total_amount / envelope.total_count).round(2)
        else
          if envelope.remaining_count == 1
            claim_amount = envelope.remaining_amount
          else
            avg = envelope.remaining_amount / envelope.remaining_count
            max_rand = avg * 2
            claim_amount = (max_rand * rand).round(2)
            claim_amount = BigDecimal("0.01") if claim_amount < BigDecimal("0.01")
            claim_amount = envelope.remaining_amount if claim_amount > envelope.remaining_amount
          end
        end

        new_remaining = envelope.remaining_amount - claim_amount
        new_count = envelope.remaining_count - 1
        new_status = new_count == 0 ? "finished" : "active"

        envelope.update!(remaining_amount: new_remaining, remaining_count: new_count, status: new_status)

        CreditRedEnvelopeClaim.create!(red_envelope_id: envelope.id, user_id: current_user.id, amount: claim_amount)

        wallet.update!(
          available_balance: wallet.available_balance + claim_amount,
          total_receive: wallet.total_receive + claim_amount,
        )

        sender = User.find_by(id: envelope.sender_id)
        CreditOrder.create!(
          order_name: "领取 @#{sender&.username} 的红包",
          payer_user_id: 0,
          payee_user_id: current_user.id,
          amount: claim_amount,
          fee_rate: 0,
          fee_amount: 0,
          actual_amount: claim_amount,
          status: "success",
          order_type: "red_envelope_receive",
          remark: envelope.message,
          trade_time: Time.current,
        )
      end

      render json: { amount: claim_amount.to_f, message: "领取成功" }
    rescue => e
      render json: { error: e.message }, status: 400
    end

    # GET /credit/redenvelope/:id.json
    # 获取红包信息（用于帖子内渲染）
    def show
      envelope = CreditRedEnvelope.find_by(id: params[:id])
      return render json: { error: "红包不存在" }, status: 404 unless envelope

      sender = User.find_by(id: envelope.sender_id)
      claims = envelope.claims.order(created_at: :desc).map do |c|
        u = User.find_by(id: c.user_id)
        { username: u&.username, amount: c.amount.to_f, claimed_at: c.created_at }
      end

      has_claimed = current_user ? envelope.claimed_by?(current_user.id) : false
      my_claim = has_claimed ? CreditRedEnvelopeClaim.find_by(red_envelope_id: envelope.id, user_id: current_user.id) : nil

      render json: {
        id: envelope.id,
        sender_username: sender&.username,
        total_amount: envelope.total_amount.to_f,
        remaining_amount: envelope.remaining_amount.to_f,
        total_count: envelope.total_count,
        remaining_count: envelope.remaining_count,
        type: envelope.envelope_type,
        message: envelope.message,
        status: envelope.status,
        require_reply: envelope.require_reply,
        expires_at: envelope.expires_at,
        claims: claims,
        has_claimed: has_claimed,
        my_amount: my_claim&.amount&.to_f || 0,
      }
    end

    # POST /credit/redenvelope/bind-post.json
    # 红包创建后绑定到帖子（发帖成功后回调）
    def bind_post
      envelope = CreditRedEnvelope.find_by(id: params[:envelope_id], sender_id: current_user.id)
      return render json: { error: "红包不存在" }, status: 404 unless envelope

      envelope.update!(topic_id: params[:topic_id], post_id: params[:post_id])
      render json: { success: true }
    end
  end
end
