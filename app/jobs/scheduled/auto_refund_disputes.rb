# frozen_string_literal: true

module Jobs
  class AutoRefundDisputes < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.credit_enabled

      auto_refund_hours = CreditSystemConfig.get_i("dispute_auto_refund_hours")
      auto_refund_hours = 168 if auto_refund_hours <= 0

      deadline = Time.current - auto_refund_hours.hours

      disputes = CreditDispute.where(status: "disputing").where("created_at < ?", deadline)

      disputes.find_each do |dispute|
        ActiveRecord::Base.transaction do
          order = CreditOrder.find_by(id: dispute.order_id, status: "disputing")
          next unless order

          # Deduct merchant
          merchant_wallet = CreditWallet.find_by(user_id: order.payee_user_id)
          if merchant_wallet
            CreditWallet.where(id: merchant_wallet.id).update_all(
              "available_balance = available_balance - #{order.amount}, " \
              "total_receive = total_receive - #{order.amount}",
            )
          end

          # Credit buyer
          buyer_wallet = CreditWallet.find_by(user_id: order.payer_user_id)
          if buyer_wallet
            CreditWallet.where(id: buyer_wallet.id).update_all(
              "available_balance = available_balance + #{order.amount}, " \
              "total_payment = total_payment - #{order.amount}",
            )
          end

          dispute.update!(status: "refund", handler_user_id: 0)
          order.update!(status: "refund")
        end

        Rails.logger.info("[AutoRefundDisputes] dispute #{dispute.id} auto-refunded")
      rescue => e
        Rails.logger.warn("[AutoRefundDisputes] dispute #{dispute.id} failed: #{e.message}")
      end
    end
  end
end
