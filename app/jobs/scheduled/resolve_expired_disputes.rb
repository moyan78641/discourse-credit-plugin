# frozen_string_literal: true

module Jobs
  class ResolveExpiredDisputes < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return unless SiteSetting.credit_enabled

      # 争议超过48h未处理，自动退款 + 额外扣卖家补偿
      compensation_rate = CreditSystemConfig.get_f("dispute_compensation_rate")

      CreditDispute.expired.find_each do |dispute|
        order = CreditOrder.find_by(id: dispute.order_id)
        next unless order

        ActiveRecord::Base.transaction do
          buyer_wallet = CreditWallet.find_by(user_id: order.payer_user_id)
          seller_wallet = CreditWallet.find_by(user_id: order.payee_user_id)

          # 退还买家全额（商品原价）
          if buyer_wallet
            buyer_wallet.update!(
              available_balance: buyer_wallet.available_balance + order.amount,
              total_payment: [buyer_wallet.total_payment - order.amount, 0].max,
            )
          end

          # 只有卖家已到账的情况才扣回
          seller_received = order.delivery_status.nil? || order.delivery_status == "delivered"
          if seller_wallet && seller_received
            seller_wallet.update!(
              available_balance: seller_wallet.available_balance - order.actual_amount,
              total_receive: [seller_wallet.total_receive - order.actual_amount, 0].max,
            )
          end

          # 额外扣卖家补偿金
          compensation = (order.amount * compensation_rate).round(2)
          if seller_wallet && compensation > 0
            seller_wallet.update!(
              available_balance: seller_wallet.available_balance - compensation,
            )

            CreditOrder.create!(
              order_name: "争议超时补偿",
              payer_user_id: order.payee_user_id,
              payee_user_id: order.payer_user_id,
              amount: compensation,
              status: "success",
              order_type: "dispute_compensation",
              remark: "争议##{dispute.id} 超时未处理，扣除#{compensation}积分补偿买家",
              trade_time: Time.current,
            )

            # 补偿给买家
            if buyer_wallet
              buyer_wallet.reload
              buyer_wallet.update!(
                available_balance: buyer_wallet.available_balance + compensation,
              )
            end
          end

          order.update!(delivery_status: "refunded", status: "refunded")

          CreditOrder.create!(
            order_name: "退款: #{order.order_name}",
            payer_user_id: order.payee_user_id,
            payee_user_id: order.payer_user_id,
            amount: order.amount,
            status: "success",
            order_type: "product_refund",
            remark: "争议##{dispute.id} 超时自动退款",
            trade_time: Time.current,
          )

          dispute.update!(
            status: "auto_refunded",
            resolution: "超时未处理，系统自动退款并扣除#{compensation}积分补偿",
            compensation_amount: compensation,
          )

          # 通知双方
          buyer = User.find_by(id: order.payer_user_id)
          seller = User.find_by(id: order.payee_user_id)

          if buyer
            PostCreator.create!(
              Discourse.system_user,
              title: "争议自动处理通知",
              raw: "您的争议（订单 #{order.order_no}）因卖家超时未处理，系统已自动退款 #{order.amount} 积分，并额外补偿 #{compensation} 积分。",
              archetype: Archetype.private_message,
              target_usernames: [buyer.username],
              skip_validations: true,
            )
          end

          if seller
            PostCreator.create!(
              Discourse.system_user,
              title: "争议超时处理通知",
              raw: "您的订单（#{order.order_no}）争议因超时未处理，系统已自动退款给买家，并额外扣除 #{compensation} 积分作为补偿。\n\n请及时处理争议，避免损失。",
              archetype: Archetype.private_message,
              target_usernames: [seller.username],
              skip_validations: true,
            )
          end
        end

        Rails.logger.info("[ResolveExpiredDisputes] dispute #{dispute.id} auto-refunded")
      rescue => e
        Rails.logger.warn("[ResolveExpiredDisputes] dispute #{dispute.id} failed: #{e.message}")
      end
    end
  end
end
