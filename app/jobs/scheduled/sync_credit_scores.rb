# frozen_string_literal: true

module Jobs
  class SyncCreditScores < ::Jobs::Scheduled
    daily at: 16.hours # UTC 16:00 = 北京时间 0:00
    sidekiq_options queue: "low"

    def execute(args)
      return unless SiteSetting.credit_enabled

      sync_count = 0

      CreditWallet.find_each(batch_size: 100) do |wallet|
        user = User.find_by(id: wallet.user_id)
        next unless user&.active

        current_score = fetch_gamification_score(user.id)
        delta = current_score - wallet.initial_leaderboard_score
        # delta 可以是负数（违规扣分后分数低于注册基准）
        target_community = [delta, 0].max

        diff = BigDecimal(target_community.to_s) - wallet.community_balance
        next if diff == 0

        ActiveRecord::Base.transaction do
          if diff > 0
            # 分数增加，加积分
            CreditWallet.where(id: wallet.id).update_all(
              "available_balance = available_balance + #{diff}, " \
              "community_balance = #{target_community}, " \
              "total_community = total_community + #{diff}, " \
              "total_receive = total_receive + #{diff}",
            )

            CreditOrder.create!(
              order_name: "社区积分同步",
              payer_user_id: 0,
              payee_user_id: wallet.user_id,
              amount: diff,
              status: "success",
              order_type: "community",
              remark: "积分增加 (当前:#{current_score}, 基准:#{wallet.initial_leaderboard_score}, 社区积分:#{target_community})",
              trade_time: Time.current,
              expires_at: Time.current,
            )
          else
            # 分数减少，扣积分（diff 是负数，取绝对值）
            deduct = diff.abs
            CreditWallet.where(id: wallet.id).update_all(
              "available_balance = GREATEST(available_balance - #{deduct}, 0), " \
              "community_balance = #{target_community}, " \
              "total_community = GREATEST(total_community - #{deduct}, 0)",
            )

            CreditOrder.create!(
              order_name: "社区积分扣减",
              payer_user_id: wallet.user_id,
              payee_user_id: 0,
              amount: deduct,
              status: "success",
              order_type: "community",
              remark: "积分扣减 (当前:#{current_score}, 基准:#{wallet.initial_leaderboard_score}, 社区积分:#{target_community})",
              trade_time: Time.current,
              expires_at: Time.current,
            )
          end
        end

        sync_count += 1
        sleep 0.05
      rescue => e
        Rails.logger.warn("[SyncCreditScores] user #{wallet.user_id} failed: #{e.message}")
      end

      Rails.logger.info("[SyncCreditScores] synced #{sync_count} users")
    end

    private

    def fetch_gamification_score(user_id)
      result = DB.query_single(
        "SELECT score FROM gamification_score_events_mv WHERE user_id = :uid LIMIT 1",
        uid: user_id,
      )
      result.first || 0
    rescue
      user = User.find_by(id: user_id)
      user&.respond_to?(:gamification_score) ? (user.gamification_score || 0) : 0
    end
  end
end
