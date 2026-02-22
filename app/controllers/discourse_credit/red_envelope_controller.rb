# frozen_string_literal: true

module ::DiscourseCredit
  class RedEnvelopeController < BaseController
    # POST /credit/redenvelope/create.json
    def create
      wallet = current_wallet!
      return unless verify_pay_key!(params[:pay_key])

      amount = params[:amount].to_d rescue 0
      count = params[:count].to_i
      envelope_type = params[:type] == "random" ? "random" : "fixed"
      message = params[:message].to_s[0..49]

      max_amount = config_get_i("red_envelope_max_amount")
      return render json: { error: "金额无效" }, status: 400 if amount <= 0
      return render json: { error: "红包金额不能超过 #{max_amount}" }, status: 400 if amount > max_amount
      return render json: { error: "人数无效" }, status: 400 if count < 1 || count > config_get_i("red_envelope_max_recipients")

      min_total = BigDecimal("0.01") * count
      return render json: { error: "红包金额太小" }, status: 400 if amount < min_total

      fee_rate = config_get_f("red_envelope_fee_rate")
      fee = (amount * fee_rate).round(2)
      total_deduct = amount + fee

      expire_hours = config_get_i("red_envelope_expire_hours")
      expire_hours = 24 if expire_hours <= 0

      envelope = nil

      ActiveRecord::Base.transaction do
        wallet.reload
        raise "余额不足" if wallet.available_balance < total_deduct

        CreditWallet.where(id: wallet.id).update_all(
          "available_balance = available_balance - #{total_deduct}, " \
          "total_payment = total_payment + #{total_deduct}",
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
          expires_at: Time.current + expire_hours.hours,
        )

        CreditOrder.create!(
          order_name: "发红包 (#{count}个)",
          payer_user_id: current_user.id,
          payee_user_id: 0,
          amount: total_deduct,
          status: "success",
          order_type: "red_envelope_send",
          remark: "#{message}#{fee > 0 ? " (手续费: #{format('%.2f', fee)})" : ""}",
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      base_url = SiteSetting.credit_frontend_url.presence || Discourse.base_url
      claim_url = "#{base_url}/credit/redenvelope/#{envelope.id}"

      render json: { id: envelope.id, url: claim_url, message: "红包创建成功" }
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
        raise "您已领取过该红包" if CreditRedEnvelopeClaim.exists?(red_envelope_id: envelope.id, user_id: current_user.id)
        raise "红包已被领完" if envelope.remaining_count <= 0

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
        new_status = new_count == 0 ? "finished" : envelope.status

        envelope.update!(
          remaining_amount: new_remaining,
          remaining_count: new_count,
          status: new_status,
        )

        CreditRedEnvelopeClaim.create!(
          red_envelope_id: envelope.id,
          user_id: current_user.id,
          amount: claim_amount,
        )

        CreditWallet.where(user_id: current_user.id).update_all(
          "available_balance = available_balance + #{claim_amount}, " \
          "total_receive = total_receive + #{claim_amount}",
        )

        sender = User.find_by(id: envelope.sender_id)
        CreditOrder.create!(
          order_name: "领取 #{sender&.username || 'unknown'} 的红包",
          payer_user_id: 0,
          payee_user_id: current_user.id,
          amount: claim_amount,
          status: "success",
          order_type: "red_envelope_receive",
          remark: envelope.message,
          trade_time: Time.current,
          expires_at: Time.current,
        )
      end

      render json: { amount: claim_amount.to_f, message: "领取成功" }
    rescue => e
      render json: { error: e.message }, status: 400
    end

    # GET /credit/redenvelope/:id.json
    def show
      envelope = CreditRedEnvelope.find_by(id: params[:id])
      return render json: { error: "红包不存在" }, status: 404 unless envelope

      sender = User.find_by(id: envelope.sender_id)
      claims = envelope.claims.order(created_at: :desc).map do |c|
        u = User.find_by(id: c.user_id)
        { user_id: c.user_id, username: u&.username, amount: c.amount.to_f, claimed_at: c.created_at }
      end

      my_claim = CreditRedEnvelopeClaim.find_by(red_envelope_id: envelope.id, user_id: current_user.id)

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
        expires_at: envelope.expires_at,
        created_at: envelope.created_at,
        claims: claims,
        has_claimed: my_claim.present?,
        my_amount: my_claim&.amount&.to_f || 0,
      }
    end

    # GET /credit/redenvelope/list.json
    def list
      list_type = params[:type] || "received"
      page = (params[:page] || 1).to_i
      page_size = 20
      offset = (page - 1) * page_size

      if list_type == "sent"
        total = CreditRedEnvelope.where(sender_id: current_user.id).count
        envelopes = CreditRedEnvelope.where(sender_id: current_user.id)
                                     .order(created_at: :desc).offset(offset).limit(page_size)
        result = envelopes.map do |e|
          {
            id: e.id, total_amount: e.total_amount.to_f, remaining_amount: e.remaining_amount.to_f,
            total_count: e.total_count, remaining_count: e.remaining_count,
            type: e.envelope_type, message: e.message, status: e.status, created_at: e.created_at,
          }
        end
      else
        total = CreditRedEnvelopeClaim.where(user_id: current_user.id).count
        claims = CreditRedEnvelopeClaim.where(user_id: current_user.id)
                                       .order(created_at: :desc).offset(offset).limit(page_size)
        result = claims.map do |c|
          e = CreditRedEnvelope.find_by(id: c.red_envelope_id)
          sender = User.find_by(id: e&.sender_id)
          {
            id: e&.id, sender_username: sender&.username, amount: c.amount.to_f,
            message: e&.message, claimed_at: c.created_at,
          }
        end
      end

      render json: { list: result, total: total, page: page, page_size: page_size }
    end
  end
end
