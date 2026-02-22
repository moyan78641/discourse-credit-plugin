# frozen_string_literal: true

module Jobs
  class RefundExpiredRedEnvelopes < ::Jobs::Scheduled
    every 30.minutes

    def execute(args)
      return unless SiteSetting.credit_enabled

      envelopes = CreditRedEnvelope.where(status: "active")
                                   .where("expires_at < ? AND remaining_amount > 0", Time.current)

      envelopes.find_each do |envelope|
        ActiveRecord::Base.transaction do
          refund_amount = envelope.remaining_amount

          envelope.update!(status: "expired", remaining_amount: 0, remaining_count: 0)

          CreditWallet.where(user_id: envelope.sender_id).update_all(
            "available_balance = available_balance + #{refund_amount}",
          )

          CreditOrder.create!(
            order_name: "红包过期退款",
            payer_user_id: 0,
            payee_user_id: envelope.sender_id,
            amount: refund_amount,
            status: "success",
            order_type: "red_envelope_refund",
            remark: "红包 ##{envelope.id} 过期退款",
            trade_time: Time.current,
            expires_at: Time.current,
          )
        end

        Rails.logger.info("[RefundRedEnvelopes] envelope #{envelope.id} refunded #{refund_amount}")
      rescue => e
        Rails.logger.warn("[RefundRedEnvelopes] envelope #{envelope.id} failed: #{e.message}")
      end
    end
  end
end
