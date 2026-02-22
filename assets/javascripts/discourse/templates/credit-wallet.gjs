import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

class CreditWalletPage extends Component {
  @tracked wallet = null;
  @tracked orders = [];
  @tracked loading = true;
  @tracked ordersLoading = false;
  @tracked error = null;
  @tracked page = 1;
  @tracked totalOrders = 0;
  @tracked orderType = "all";
  @tracked showPayKeyModal = false;
  @tracked oldKey = "";
  @tracked newKey = "";
  @tracked confirmKey = "";
  @tracked payKeyError = null;
  @tracked payKeySaving = false;

  constructor() {
    super(...arguments);
    this.loadWallet();
  }

  async loadWallet() {
    try {
      const data = await ajax("/credit/wallet.json");
      this.wallet = data;
      await this.loadOrders();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally {
      this.loading = false;
    }
  }

  async loadOrders() {
    this.ordersLoading = true;
    try {
      const data = await ajax(`/credit/orders.json?page=${this.page}&type=${this.orderType}`);
      this.orders = data.list || [];
      this.totalOrders = data.total || 0;
    } catch (_) { /* ignore */ }
    finally { this.ordersLoading = false; }
  }

  @action changeOrderType(e) {
    this.orderType = e.target.value;
    this.page = 1;
    this.loadOrders();
  }

  get noPrevPage() { return this.page <= 1; }

  @action prevPage() {
    if (this.page > 1) { this.page--; this.loadOrders(); }
  }

  @action nextPage() {
    if (this.page * 20 < this.totalOrders) { this.page++; this.loadOrders(); }
  }

  @action openPayKeyModal() {
    this.showPayKeyModal = true;
    this.oldKey = "";
    this.newKey = "";
    this.confirmKey = "";
    this.payKeyError = null;
  }

  @action closePayKeyModal() {
    this.showPayKeyModal = false;
  }

  @action updateOldKey(e) { this.oldKey = e.target.value; }
  @action updateNewKey(e) { this.newKey = e.target.value; }
  @action updateConfirmKey(e) { this.confirmKey = e.target.value; }
  @action stopPropagation(e) { e.stopPropagation(); }

  @action async savePayKey() {
    if (!/^\d{6}$/.test(this.newKey)) {
      this.payKeyError = "支付密码必须是6位数字";
      return;
    }
    if (this.newKey !== this.confirmKey) {
      this.payKeyError = "两次输入不一致";
      return;
    }
    this.payKeySaving = true;
    this.payKeyError = null;
    try {
      await ajax("/credit/pay-key.json", {
        type: "PUT",
        data: { new_key: this.newKey, old_key: this.oldKey || undefined },
      });
      this.showPayKeyModal = false;
      this.wallet = { ...this.wallet, has_pay_key: true };
    } catch (e) {
      this.payKeyError = e.jqXHR?.responseJSON?.error || "设置失败";
    } finally {
      this.payKeySaving = false;
    }
  }

  <template>
    <div class="credit-wallet-page">
      <h2>💰 积分钱包</h2>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{else if this.wallet}}
        <div class="credit-wallet-card">
          <div class="wallet-header">
            <div class="wallet-user">
              <span class="wallet-username">{{this.wallet.username}}</span>
              <span class="wallet-level">{{this.wallet.pay_level_name}}</span>
              {{#if this.wallet.is_admin}}<span class="wallet-admin-badge">管理员</span>{{/if}}
            </div>
            <div class="wallet-balance-main">
              <span class="balance-label">可用余额</span>
              <span class="balance-value">{{this.wallet.available_balance}}</span>
            </div>
          </div>
          <div class="wallet-stats">
            <div class="stat-item"><span class="stat-label">总收入</span><span class="stat-value">{{this.wallet.total_receive}}</span></div>
            <div class="stat-item"><span class="stat-label">总支出</span><span class="stat-value">{{this.wallet.total_payment}}</span></div>
            <div class="stat-item"><span class="stat-label">总转账</span><span class="stat-value">{{this.wallet.total_transfer}}</span></div>
            <div class="stat-item"><span class="stat-label">社区积分</span><span class="stat-value">{{this.wallet.community_balance}}</span></div>
          </div>
          <div class="wallet-actions">
            <a href="/credit/transfer" class="btn btn-primary">转账</a>
            <a href="/credit/redenvelope" class="btn btn-default">红包</a>
            <a href="/credit/dashboard" class="btn btn-default">统计</a>
            <a href="/credit/merchant" class="btn btn-default">商户</a>
            <button class="btn btn-default" type="button" {{on "click" this.openPayKeyModal}}>
              {{if this.wallet.has_pay_key "修改支付密码" "设置支付密码"}}
            </button>
            {{#if this.wallet.is_admin}}
              <a href="/credit/admin" class="btn btn-danger">管理后台</a>
            {{/if}}
          </div>
        </div>

        <div class="credit-orders-section">
          <div class="orders-header">
            <h3>交易记录</h3>
            <select class="order-type-select" {{on "change" this.changeOrderType}}>
              <option value="all">全部</option>
              <option value="income">收入</option>
              <option value="expense">支出</option>
            </select>
          </div>

          {{#if this.ordersLoading}}
            <p class="loading-text">加载中...</p>
          {{else if this.orders.length}}
            <div class="credit-orders-list">
              {{#each this.orders as |order|}}
                <div class="credit-order-row {{if order.is_income 'income' 'expense'}}">
                  <div class="order-info">
                    <span class="order-name">{{order.order_name}}</span>
                    <span class="order-meta">{{order.type}} · {{order.status}}</span>
                  </div>
                  <span class="order-amount">{{if order.is_income "+" "-"}}{{order.amount}}</span>
                </div>
              {{/each}}
            </div>
            <div class="credit-pagination">
              <button class="btn btn-small" type="button" disabled={{this.noPrevPage}} {{on "click" this.prevPage}}>上一页</button>
              <span>第 {{this.page}} 页 / 共 {{this.totalOrders}} 条</span>
              <button class="btn btn-small" type="button" {{on "click" this.nextPage}}>下一页</button>
            </div>
          {{else}}
            <p class="no-data-text">暂无交易记录</p>
          {{/if}}
        </div>
      {{/if}}

      {{#if this.showPayKeyModal}}
        <div class="credit-modal-overlay" {{on "click" this.closePayKeyModal}}>
          <div class="credit-modal" role="dialog" {{on "click" this.stopPropagation}}>
            <h3>{{if this.wallet.has_pay_key "修改支付密码" "设置支付密码"}}</h3>
            {{#if this.payKeyError}}
              <div class="credit-error">{{this.payKeyError}}</div>
            {{/if}}
            {{#if this.wallet.has_pay_key}}
              <div class="form-row">
                <label>原密码</label>
                <input type="password" maxlength="6" placeholder="请输入原6位数字密码" {{on "input" this.updateOldKey}} />
              </div>
            {{/if}}
            <div class="form-row">
              <label>新密码</label>
              <input type="password" maxlength="6" placeholder="请输入6位数字密码" {{on "input" this.updateNewKey}} />
            </div>
            <div class="form-row">
              <label>确认密码</label>
              <input type="password" maxlength="6" placeholder="再次输入" {{on "input" this.updateConfirmKey}} />
            </div>
            <div class="credit-modal-actions">
              <button class="btn btn-default" type="button" {{on "click" this.closePayKeyModal}}>取消</button>
              <button class="btn btn-primary" type="button" disabled={{this.payKeySaving}} {{on "click" this.savePayKey}}>
                {{if this.payKeySaving "保存中..." "确定"}}
              </button>
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditWalletPage /></template>);
