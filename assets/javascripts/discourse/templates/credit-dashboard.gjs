import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

class CreditDashboardPage extends Component {
  @tracked overview = null;
  @tracked dailyStats = [];
  @tracked recent = [];
  @tracked topCustomers = [];
  @tracked loading = true;

  constructor() {
    super(...arguments);
    this.loadAll();
  }

  async loadAll() {
    try {
      const [ov, ds, rc, tc] = await Promise.all([
        ajax("/credit/dashboard/overview.json"),
        ajax("/credit/dashboard/daily-stats.json?days=7"),
        ajax("/credit/dashboard/recent.json?limit=10"),
        ajax("/credit/dashboard/top-customers.json?days=7&limit=5"),
      ]);
      this.overview = ov;
      this.dailyStats = ds.stats || [];
      this.recent = rc.transactions || [];
      this.topCustomers = tc.customers || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  <template>
    <div class="credit-dashboard-page">
      <h2>📊 统计面板</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">← 返回钱包</a>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else}}
        {{#if this.overview}}
          <div class="dashboard-overview">
            <div class="overview-card">
              <h4>今日</h4>
              <div class="ov-row"><span>收入</span><span class="income">+{{this.overview.today.income}}</span></div>
              <div class="ov-row"><span>支出</span><span class="expense">-{{this.overview.today.expense}}</span></div>
            </div>
            <div class="overview-card">
              <h4>本周</h4>
              <div class="ov-row"><span>收入</span><span class="income">+{{this.overview.week.income}}</span></div>
              <div class="ov-row"><span>支出</span><span class="expense">-{{this.overview.week.expense}}</span></div>
            </div>
            <div class="overview-card">
              <h4>本月</h4>
              <div class="ov-row"><span>收入</span><span class="income">+{{this.overview.month.income}}</span></div>
              <div class="ov-row"><span>支出</span><span class="expense">-{{this.overview.month.expense}}</span></div>
            </div>
          </div>
        {{/if}}

        {{#if this.dailyStats.length}}
          <div class="dashboard-section">
            <h3>近7日收支</h3>
            <div class="daily-stats-table">
              <div class="ds-header">
                <span>日期</span><span>收入</span><span>支出</span>
              </div>
              {{#each this.dailyStats as |s|}}
                <div class="ds-row">
                  <span>{{s.date}}</span>
                  <span class="income">+{{s.income}}</span>
                  <span class="expense">-{{s.expense}}</span>
                </div>
              {{/each}}
            </div>
          </div>
        {{/if}}

        {{#if this.topCustomers.length}}
          <div class="dashboard-section">
            <h3>Top 客户（近7日）</h3>
            <div class="top-customers-list">
              {{#each this.topCustomers as |c|}}
                <div class="tc-row">
                  <span class="tc-user">{{c.username}}</span>
                  <span class="tc-amount">{{c.total_amount}} 积分</span>
                  <span class="tc-count">{{c.order_count}} 笔</span>
                </div>
              {{/each}}
            </div>
          </div>
        {{/if}}

        {{#if this.recent.length}}
          <div class="dashboard-section">
            <h3>最近交易</h3>
            <div class="credit-orders-list">
              {{#each this.recent as |order|}}
                <div class="credit-order-row {{if order.is_income 'income' 'expense'}}">
                  <div class="order-info">
                    <span class="order-name">{{order.order_name}}</span>
                    <span class="order-meta">{{order.type}} · {{order.status}}</span>
                  </div>
                  <span class="order-amount">{{if order.is_income "+" "-"}}{{order.amount}}</span>
                </div>
              {{/each}}
            </div>
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditDashboardPage /></template>);
