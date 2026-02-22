# frozen_string_literal: true

module Jobs
  class ExpireCreditOrders < ::Jobs::Scheduled
    every 5.minutes

    def execute(args)
      return unless SiteSetting.credit_enabled

      count = CreditOrder.where(status: "pending")
                         .where("expires_at < ?", Time.current)
                         .update_all(status: "expired")

      Rails.logger.info("[ExpireCreditOrders] expired #{count} orders") if count > 0
    end
  end
end
