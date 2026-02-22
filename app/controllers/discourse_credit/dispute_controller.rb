# frozen_string_literal: true

module ::DiscourseCredit
  class DisputeController < BaseController
    # POST /credit/disputes.json — list my initiated disputes
    def list
      page = (params[:page] || 1).to_i
      page_size = params[:page_size].present? ? [[params[:page_size].to_i, 1].max, 100].min : 20
      status_filter = params[:status]

      scope = CreditDispute.where(initiator_user_id: current_user.id)
      scope = scope.where(status: status_filter) if status_filter.present?

      total = scope.count
      disputes = scope.order(created_at: :desc).offset((page - 1) * page_size).limit(page_size)

      render json: { total: total, page: page, page_size: page_size, disputes: build_dispute_list(disputes) }
    end

    # POST /credit/disputes/merchant.json — disputes on my orders as merchant
    def list_merchant
      page = (params[:page] || 1).to_i
      page_size = params[:page_size].present? ? [[params[:page_size].to_i, 1].max, 100].min : 20
      status_filter = params[:status]

      order_ids = CreditOrder.where(payee_user_id: current_user.id).pluck(:id)
      scope = CreditDispute.where(order_id: order_ids)
      scope = scope.where(status: status_filter) if status_filter.present?

      total = scope.count
      disputes = scope.order(created_at: :desc).offset((page - 1) * page_size).limit(page_size)

      render json: { total: total, page: page, page_size: page_size, disputes: build_dispute_list(disputes) }
    end

    # GET /credit/disputable-orders.json — orders eligible for dispute
    def disputable_orders
      dispute_hours = config_get_i("dispute_time_window_hours")
      dispute_hours = 72 if dispute_hours <= 0
      cutoff = Time.current - dispute_hours.hours

      existing_dispute_order_ids = CreditDispute.pluck(:order_id)

      orders = CreditOrder.where(payer_user_id: current_user.id, status: "success")
                          .where(order_type: %w[payment transfer])
                          .where("COALESCE(trade_time, created_at) > ?", cutoff)
                          .where.not(id: existing_dispute_order_ids)
                          .order(created_at: :desc)
                          .limit(50)

      user_ids = orders.map(&:payee_user_id).uniq.reject(&:zero?)
      user_map = User.where(id: user_ids).index_by(&:id)

      list = orders.map do |o|
        {
          id: o.id,
          order_name: o.order_name,
          amount: o.amount.to_f,
          payee_username: user_map[o.payee_user_id]&.username,
          created_at: o.created_at,
        }
      end

      render json: { orders: list }
    end

    # POST /credit/dispute.json — create dispute
    def create
      order_id = params[:order_id].to_i
      reason = params[:reason].to_s[0..499]
      return render json: { error: "请填写争议原因" }, status: 400 if reason.blank?

      dispute_hours = config_get_i("dispute_time_window_hours")
      dispute_hours = 72 if dispute_hours <= 0

      ActiveRecord::Base.transaction do
        order = CreditOrder.where(
          id: order_id,
          payer_user_id: current_user.id,
          status: "success",
        ).where(order_type: %w[payment transfer]).first
        raise "订单不存在或不符合争议条件" unless order

        check_time = order.trade_time || order.created_at
        raise "订单已超过争议时间窗口" if Time.current > check_time + dispute_hours.hours

        raise "该订单已存在争议记录" if CreditDispute.exists?(order_id: order_id)

        CreditDispute.create!(
          order_id: order_id,
          initiator_user_id: current_user.id,
          reason: reason,
          status: "disputing",
        )

        order.update!(status: "disputing")
      end

      render json: { ok: true }
    rescue => e
      msg = %w[订单不存在 争议时间 已存在争议].find { |k| e.message.include?(k) }
      render json: { error: msg ? e.message : "发起争议失败" }, status: 400
    end

    # POST /credit/dispute/review.json — merchant review (refund or close)
    def review
      dispute_id = params[:dispute_id].to_i
      new_status = params[:status].to_s
      reason = params[:reason].to_s

      return render json: { error: "状态无效" }, status: 400 unless %w[refund closed].include?(new_status)
      return render json: { error: "拒绝退款时必须提供理由" }, status: 400 if new_status == "closed" && reason.blank?

      ActiveRecord::Base.transaction do
        dispute = CreditDispute.lock.find_by(id: dispute_id, status: "disputing")
        raise "争议不存在" unless dispute

        order = CreditOrder.find_by(id: dispute.order_id, payee_user_id: current_user.id, status: "disputing")
        raise "您不是该订单的商家" unless order

        if new_status == "refund"
          # Refund: deduct merchant, credit buyer
          merchant_wallet = CreditWallet.find_by(user_id: current_user.id)
          CreditWallet.where(id: merchant_wallet.id).update_all(
            "available_balance = available_balance - #{order.amount}, " \
            "total_receive = total_receive - #{order.amount}",
          ) if merchant_wallet

          buyer_wallet = CreditWallet.find_by(user_id: order.payer_user_id)
          CreditWallet.where(id: buyer_wallet.id).update_all(
            "available_balance = available_balance + #{order.amount}, " \
            "total_payment = total_payment - #{order.amount}",
          ) if buyer_wallet

          dispute.update!(status: "refund", handler_user_id: current_user.id)
          order.update!(status: "refund")
        else
          new_reason = dispute.reason + " [商家拒绝理由: #{reason}]"
          dispute.update!(status: "closed", handler_user_id: current_user.id, reason: new_reason)
          order.update!(status: "refused")
        end
      end

      render json: { ok: true }
    rescue => e
      msg = %w[争议不存在 不是该订单].find { |k| e.message.include?(k) }
      render json: { error: msg ? e.message : "处理失败" }, status: 400
    end

    # POST /credit/dispute/close.json — initiator withdraws dispute
    def close
      dispute_id = params[:dispute_id].to_i

      ActiveRecord::Base.transaction do
        dispute = CreditDispute.lock.find_by(id: dispute_id, initiator_user_id: current_user.id, status: "disputing")
        raise "争议不存在" unless dispute

        order = CreditOrder.find_by(id: dispute.order_id, status: "disputing")
        raise "订单不存在" unless order

        dispute.update!(status: "closed", handler_user_id: current_user.id)
        order.update!(status: "success")
      end

      render json: { ok: true }
    rescue => e
      render json: { error: e.message.include?("争议不存在") ? e.message : "关闭失败" }, status: 400
    end

    private

    def build_dispute_list(disputes)
      order_ids = disputes.map(&:order_id)
      orders = CreditOrder.where(id: order_ids).index_by(&:id)
      user_ids = disputes.flat_map { |d| [d.initiator_user_id, d.handler_user_id] }.compact.uniq
      user_ids += orders.values.flat_map { |o| [o.payer_user_id, o.payee_user_id] }.uniq
      user_map = User.where(id: user_ids.reject(&:zero?)).index_by(&:id)

      disputes.map do |d|
        o = orders[d.order_id]
        {
          id: d.id,
          order_id: d.order_id,
          order_name: o&.order_name,
          amount: o&.amount&.to_f,
          reason: d.reason,
          status: d.status,
          initiator_username: user_map[d.initiator_user_id]&.username,
          payee_username: o ? user_map[o.payee_user_id]&.username : nil,
          handler_username: d.handler_user_id ? user_map[d.handler_user_id]&.username : nil,
          created_at: d.created_at,
          updated_at: d.updated_at,
        }
      end
    end
  end
end
