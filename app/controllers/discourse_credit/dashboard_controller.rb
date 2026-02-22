# frozen_string_literal: true

module ::DiscourseCredit
  class DashboardController < BaseController
    # GET /credit/dashboard/daily-stats.json?days=7
    def daily_stats
      days = [[params[:days].to_i, 1].max, 30].min
      days = 7 if days == 1
      uid = current_user.id
      start_date = days.days.ago.beginning_of_day

      income_rows = CreditOrder
        .where("payee_user_id = ? AND payer_user_id != ? AND status = ? AND created_at >= ?", uid, uid, "success", start_date)
        .group("DATE(created_at)")
        .pluck(Arel.sql("DATE(created_at) as d, COALESCE(SUM(amount), 0)"))
        .to_h

      expense_rows = CreditOrder
        .where("payer_user_id = ? AND payee_user_id != ? AND status = ? AND created_at >= ?", uid, uid, "success", start_date)
        .group("DATE(created_at)")
        .pluck(Arel.sql("DATE(created_at) as d, COALESCE(SUM(amount), 0)"))
        .to_h

      stats = (0...days).map do |i|
        date = (start_date + i.days).to_date.to_s
        { date: date, income: (income_rows[date] || 0).to_f, expense: (expense_rows[date] || 0).to_f }
      end

      render json: { stats: stats }
    end

    # GET /credit/dashboard/overview.json
    def overview
      uid = current_user.id
      today_start = Time.current.beginning_of_day
      week_start = Time.current.beginning_of_week
      month_start = Time.current.beginning_of_month

      render json: {
        today: period_stats(uid, today_start),
        week: period_stats(uid, week_start),
        month: period_stats(uid, month_start),
      }
    end

    # GET /credit/dashboard/recent.json?limit=10
    def recent
      uid = current_user.id
      limit = [[params[:limit].to_i, 1].max, 50].min
      limit = 10 if limit == 1

      orders = CreditOrder.where("payer_user_id = ? OR payee_user_id = ?", uid, uid)
                          .order(created_at: :desc).limit(limit)

      user_ids = orders.flat_map { |o| [o.payer_user_id, o.payee_user_id] }.uniq.reject(&:zero?)
      user_map = User.where(id: user_ids).index_by(&:id)

      list = orders.map do |o|
        {
          id: o.id,
          order_name: o.order_name,
          amount: o.amount.to_f,
          status: o.status,
          type: o.order_type,
          is_income: o.payee_user_id == uid && o.payer_user_id != uid,
          payer_username: user_map[o.payer_user_id]&.username,
          payee_username: user_map[o.payee_user_id]&.username,
          created_at: o.created_at,
        }
      end

      render json: { transactions: list }
    end

    # GET /credit/dashboard/top-customers.json?days=7&limit=5
    def top_customers
      uid = current_user.id
      days = [[params[:days].to_i, 1].max, 30].min
      days = 7 if days == 1
      limit = [[params[:limit].to_i, 1].max, 20].min
      limit = 5 if limit == 1
      start_date = days.days.ago

      rows = CreditOrder
        .where(payee_user_id: uid, status: "success")
        .where.not(payer_user_id: [0, uid])
        .where(order_type: %w[payment online transfer])
        .where("created_at >= ?", start_date)
        .group(:payer_user_id)
        .order(Arel.sql("SUM(amount) DESC"))
        .limit(limit)
        .pluck(Arel.sql("payer_user_id, SUM(amount) as total_amount, COUNT(*) as order_count"))

      user_ids = rows.map(&:first)
      user_map = User.where(id: user_ids).index_by(&:id)

      customers = rows.map do |uid_r, total, count|
        { user_id: uid_r, username: user_map[uid_r]&.username, total_amount: total.to_f, order_count: count }
      end

      render json: { customers: customers }
    end

    private

    def period_stats(uid, since)
      income = CreditOrder
        .where("payee_user_id = ? AND payer_user_id != ? AND status = ? AND created_at >= ?", uid, uid, "success", since)
        .sum(:amount).to_f

      expense = CreditOrder
        .where("payer_user_id = ? AND payee_user_id != ? AND status = ? AND created_at >= ?", uid, uid, "success", since)
        .sum(:amount).to_f

      { income: income, expense: expense }
    end
  end
end
