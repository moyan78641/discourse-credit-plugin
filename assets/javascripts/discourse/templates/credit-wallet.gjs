import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

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
  @tracked selectedOrder = null;
  @tracked orderDetail = null;
  @tracked detailLoading = false;

  constructor() {
    super(...arguments);
    this.loadWallet();
  }

  async loadWallet() {
    try {
      const data = await ajax("/credit/wallet.json");
      this.wallet = data;
      if (data.has_pay_key) await this.loadOrders();
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
  get noNextPage() { return this.page * 20 >= this.totalOrders; }
  get needsPayKey() { return this.wallet && !this.wallet.has_pay_key; }

  @action prevPage() { if (this.page > 1) { this.page--; this.loadOrders(); } }
  @action nextPage() { if (!this.noNextPage) { this.page++; this.loadOrders(); } }

  @action openPayKeyModal() {
    this.showPayKeyModal = true;
    this.oldKey = ""; this.newKey = ""; this.confirmKey = ""; this.payKeyError = null;
  }
  @action closePayKeyModal() { this.showPayKeyModal = false; }
  @action updateOldKey(e) { this.oldKey = e.target.value; }
  @action updateNewKey(e) { this.newKey = e.target.value; }
  @action updateConfirmKey(e) { this.confirmKey = e.target.value; }
  @action stopPropagation(e) { e.stopPropagation(); }

  @action async savePayKey() {
    if (!/^\d{6}$/.test(this.newKey)) { this.payKeyError = "支付密码必须是6位数字"; return; }
    if (this.newKey !== this.confirmKey) { this.payKeyError = "两次输入不一致"; return; }
    this.payKeySaving = true; this.payKeyError = null;
    try {
      await ajax("/credit/pay-key.json", { type: "PUT", data: { new_key: this.newKey, old_key: this.oldKey || undefined } });
      this.showPayKeyModal = false;
      this.wallet = { ...this.wallet, has_pay_key: true };
      await this.loadOrders();
    } catch (e) {
      this.payKeyError = e.jqXHR?.responseJSON?.error || "设置失败";
    } finally { this.payKeySaving = false; }
  }

  @action async openOrderDetail(orderId) {
    this.selectedOrder = orderId;
    this.detailLoading = true;
    this.orderDetail = null;
    try {
      const data = await ajax(`/credit/order/${orderId}.json`);
      this.orderDetail = data;
    } catch (_) { /* ignore */ }
    finally { this.detailLoading = false; }
  }

  @action closeOrderDetail() { this.selectedOrder = null; this.orderDetail = null; }

  get orderTypeLabel() {
    const map = { tip: "打赏", product: "商品购买", red_envelope_send: "发红包", red_envelope_receive: "领红包", red_envelope_refund: "红包退回", community: "社区", receive: "收入", payment: "支出" };
    return (t) => map[t] || t;
  }

  <template>
    <div class="credit-wallet-page">
      <h2>{{icon "wallet"}} 积分钱包</h2>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{else if this.wallet}}

        {{#if this.needsPayKey}}
          <div class="credit-paykey-required">
            <div class="paykey-icon">{{icon "lock"}}</div>
            <h3>请先设置支付密码</h3>
            <p>为了保障您的资产安全，使用积分系统前需要先设置6位数字支付密码。</p>
            {{#if this.payKeyError}}<div class="credit-error">{{this.payKeyError}}</div>{{/if}}
            <div class="paykey-form">
              <div class="form-row"><label>支付密码</label><input type="password" maxlength="6" placeholder="请输入6位数字密码" {{on "input" this.updateNewKey}} /></div>
              <div class="form-row"><label>确认密码</label><input type="password" maxlength="6" placeholder="再次输入" {{on "input" this.updateConfirmKey}} /></div>
              <button class="btn btn-primary btn-large" type="button" disabled={{this.payKeySaving}} {{on "click" this.savePayKey}}>{{if this.payKeySaving "设置中..." "确认设置"}}</button>
            </div>
          </div>
        {{else}}
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
              <div class="stat-item"><span class="stat-label">基准分数</span><span class="stat-value">{{this.wallet.initial_leaderboard_score}}</span></div>
            </div>
            <div class="wallet-actions">
              <a href="/credit/merchant" class="btn btn-default">{{icon "store"}} 商户</a>
              <button class="btn btn-default" type="button" {{on "click" this.openPayKeyModal}}>{{icon "key"}} 修改密码</button>
              {{#if this.wallet.is_admin}}<a href="/credit/admin" class="btn btn-danger">{{icon "gears"}} 管理后台</a>{{/if}}
            </div>
          </div>

          <div class="credit-orders-section">
            <div class="orders-header">
              <h3>{{icon "receipt"}} 交易记录</h3>
              <select class="order-type-select" {{on "change" this.changeOrderType}}>
                <option value="all">全部</option>
                <option value="income">收入</option>
                <option value="expense">支出</option>
                <option value="tip">打赏</option>
                <option value="red_envelope">红包</option>
                <option value="product">商品</option>
                <option value="community">社区</option>
              </select>
            </div>

            {{#if this.ordersLoading}}
              <p class="loading-text">加载中...</p>
            {{else if this.orders.length}}
              <div class="credit-orders-list">
                {{#each this.orders as |order|}}
                  <div class="credit-order-row {{if order.is_income 'income' 'expense'}}" role="button" {{on "click" (fn this.openOrderDetail order.id)}}>
                    <div class="order-info">
                      <span class="order-name">{{order.order_name}}</span>
                      <span class="order-meta">{{order.type}} · {{order.status}} · {{order.order_no}}</span>
                    </div>
                    <span class="order-amount">{{if order.is_income "+" "-"}}{{order.amount}}</span>
                  </div>
                {{/each}}
              </div>
              <div class="credit-pagination">
                <button class="btn btn-small" type="button" disabled={{this.noPrevPage}} {{on "click" this.prevPage}}>上一页</button>
                <span>第 {{this.page}} 页 / 共 {{this.totalOrders}} 条</span>
                <button class="btn btn-small" type="button" disabled={{this.noNextPage}} {{on "click" this.nextPage}}>下一页</button>
              </div>
            {{else}}
              <p class="no-data-text">暂无交易记录</p>
            {{/if}}
          </div>
        {{/if}}
      {{/if}}

      {{!-- 订单详情弹窗 --}}
      {{#if this.selectedOrder}}
        <div class="credit-modal-overlay" {{on "click" this.closeOrderDetail}}>
          <div class="credit-order-detail-modal" role="dialog" {{on "click" this.stopPropagation}}>
            {{#if this.detailLoading}}
              <p class="loading-text">加载中...</p>
            {{else if this.orderDetail}}
              <div class="order-receipt">
                <div class="receipt-header">
                  <h3>积分流转详情</h3>
                  <span class="receipt-time">{{this.orderDetail.created_at}}</span>
                </div>
                <div class="receipt-amount">
                  <span class="receipt-amount-label">交易金额</span>
                  <span class="receipt-amount-value">{{this.orderDetail.amount}}</span>
                </div>
                <div class="receipt-rows">
                  <div class="receipt-row"><span class="receipt-label">订单号</span><span class="receipt-value mono">{{this.orderDetail.order_no}}</span></div>
                  <div class="receipt-row"><span class="receipt-label">类型</span><span class="receipt-value">{{this.orderDetail.order_type}}</span></div>
                  <div class="receipt-row"><span class="receipt-label">状态</span><span class="receipt-value">{{this.orderDetail.status}}</span></div>
                  <div class="receipt-row"><span class="receipt-label">付款方</span><span class="receipt-value">{{this.orderDetail.payer_username}}</span></div>
                  <div class="receipt-row"><span class="receipt-label">收款方</span><span class="receipt-value">{{this.orderDetail.payee_username}}</span></div>
                  <div class="receipt-row fee-row"><span class="receipt-label">费率</span><span class="receipt-value">{{this.orderDetail.fee_rate}} ({{this.orderDetail.fee_amount}} 积分)</span></div>
                  <div class="receipt-row fee-row"><span class="receipt-label">实际到账</span><span class="receipt-value highlight">{{this.orderDetail.actual_amount}}</span></div>
                  {{#if this.orderDetail.remark}}<div class="receipt-row"><span class="receipt-label">备注</span><span class="receipt-value">{{this.orderDetail.remark}}</span></div>{{/if}}
                  {{#if this.orderDetail.trade_time}}<div class="receipt-row"><span class="receipt-label">交易时间</span><span class="receipt-value">{{this.orderDetail.trade_time}}</span></div>{{/if}}
                </div>
                <div class="receipt-footer">Sparkloc Credit</div>
              </div>
            {{/if}}
            <button class="btn btn-default btn-small" type="button" {{on "click" this.closeOrderDetail}}>关闭</button>
          </div>
        </div>
      {{/if}}

      {{!-- 修改密码弹窗 --}}
      {{#if this.showPayKeyModal}}
        <div class="credit-modal-overlay" {{on "click" this.closePayKeyModal}}>
          <div class="credit-modal" role="dialog" {{on "click" this.stopPropagation}}>
            <h3>{{icon "key"}} 修改支付密码</h3>
            {{#if this.payKeyError}}<div class="credit-error">{{this.payKeyError}}</div>{{/if}}
            <div class="form-row"><label>原密码</label><input type="password" maxlength="6" placeholder="请输入原6位数字密码" {{on "input" this.updateOldKey}} /></div>
            <div class="form-row"><label>新密码</label><input type="password" maxlength="6" placeholder="请输入6位数字密码" {{on "input" this.updateNewKey}} /></div>
            <div class="form-row"><label>确认密码</label><input type="password" maxlength="6" placeholder="再次输入" {{on "input" this.updateConfirmKey}} /></div>
            <div class="credit-modal-actions">
              <button class="btn btn-default" type="button" {{on "click" this.closePayKeyModal}}>取消</button>
              <button class="btn btn-primary" type="button" disabled={{this.payKeySaving}} {{on "click" this.savePayKey}}>{{if this.payKeySaving "保存中..." "确定"}}</button>
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditWalletPage /></template>);
