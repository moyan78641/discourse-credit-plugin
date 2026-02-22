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
        baseline = wallet.initial_leaderboard_score
        delta = current_score - baseline

        # 没变化就跳过
        next if delta == 0

        ActiveRecord::Base.transaction do
          if delta > 0
            # 分数比基准高，发积分
            CreditWallet.where(id: wallet.id).update_all(
              "available_balance = available_balance + #{delta}, " \
              "community_balance = community_balance + #{delta}, " \
              "total_community = total_community + #{delta}, " \
              "total_receive = total_receive + #{delta}, " \
              "initial_leaderboard_score = #{current_score}",
            )

            CreditOrder.create!(
              order_name: "社区积分发放",
              payer_user_id: 0,
              payee_user_id: wallet.user_id,
              amount: delta,
              status: "success",
              order_type: "community",
              remark: "社区划转 #{delta} 积分",
              trade_time: Time.current,
            )
          else
            # 分数比基准低，扣积分
            deduct = delta.abs
            CreditWallet.where(id: wallet.id).update_all(
              "available_balance = GREATEST(available_balance - #{deduct}, 0), " \
              "community_balance = GREATEST(community_balance - #{deduct}, 0), " \
              "total_community = GREATEST(total_community - #{deduct}, 0), " \
              "initial_leaderboard_score = #{current_score}",
            )

            CreditOrder.create!(
              order_name: "社区积分扣减",
              payer_user_id: wallet.user_id,
              payee_user_id: 0,
              amount: deduct,
              status: "success",
              order_type: "community",
              remark: "社区扣减 #{deduct} 积分",
              trade_time: Time.current,
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
