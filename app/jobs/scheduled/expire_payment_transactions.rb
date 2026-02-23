# frozen_string_literal: true

module Jobs
  class ExpirePaymentTransactions < ::Jobs::Scheduled
    every 5.minutes

    def execute(args)
      return unless SiteSetting.credit_enabled

      count = CreditPaymentTransaction
        .where(status: "pending")
        .where("expires_at < ?", Time.current)
        .update_all(status: "expired")

      Rails.logger.info("[ExpirePaymentTransactions] expired #{count} transactions") if count > 0
    end
  end
end
