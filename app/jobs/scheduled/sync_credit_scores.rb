# frozen_string_literal: true

module Jobs
  class SyncCreditScores < ::Jobs::Scheduled
    every 1.day
    sidekiq_options queue: "low"

    def execute(args)
      return unless SiteSetting.credit_enabled

      sync_count = 0

      CreditWallet.find_each(batch_size: 100) do |wallet|
        user = User.find_by(id: wallet.user_id)
        next unless user&.active

        # Get current gamification score via direct DB query
        current_score = fetch_gamification_score(user.id)
        next if current_score <= 0

        delta = current_score - wallet.initial_leaderboard_score
        next if delta <= 0

        already_synced = wallet.community_balance >= delta
        next if already_synced

        to_add = BigDecimal(delta.to_s) - wallet.community_balance
        next if to_add <= 0

        ActiveRecord::Base.transaction do
          CreditWallet.where(id: wallet.id).update_all(
            "available_balance = available_balance + #{to_add}, " \
            "community_balance = #{delta}, " \
            "total_community = total_community + #{to_add}, " \
            "total_receive = total_receive + #{to_add}",
          )

          CreditOrder.create!(
            order_name: "社区积分同步",
            payer_user_id: 0,
            payee_user_id: wallet.user_id,
            amount: to_add,
            status: "success",
            order_type: "community",
            remark: "Leaderboard 积分同步 (当前:#{current_score}, 基准:#{wallet.initial_leaderboard_score}, 差值:#{delta})",
            trade_time: Time.current,
            expires_at: Time.current,
          )
        end

        sync_count += 1
        sleep 0.05 # Small delay between batches
      rescue => e
        Rails.logger.warn("[SyncCreditScores] user #{wallet.user_id} failed: #{e.message}")
      end

      Rails.logger.info("[SyncCreditScores] synced #{sync_count} users")
    end

    private

    def fetch_gamification_score(user_id)
      # Direct query to gamification plugin's table
      result = DB.query_single(
        "SELECT score FROM gamification_score_events_mv WHERE user_id = :uid LIMIT 1",
        uid: user_id,
      )
      result.first || 0
    rescue
      # Fallback: try user custom field or gamification_score column
      user = User.find_by(id: user_id)
      user&.respond_to?(:gamification_score) ? (user.gamification_score || 0) : 0
    end
  end
end
