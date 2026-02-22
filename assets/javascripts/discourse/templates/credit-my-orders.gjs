import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq, not } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

class CreditMyOrdersPage extends Component {
  @tracked orders = [];
  @tracked loading = true;
  @tracked error = null;
  @tracked disputeOrderId = null;
  @tracked disputeReason = "";
  @tracked disputing = false;

  constructor() {
    super(...arguments);
    this.loadOrders();
  }

  async loadOrders() {
    try {
      const data = await ajax("/credit/my-orders.json");
      this.orders = data.orders || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  @action openDispute(orderId) { this.disputeOrderId = orderId; this.disputeReason = ""; this.error = null; }
  @action cancelDispute() { this.disputeOrderId = null; }
  @action updateDisputeReason(e) { this.disputeReason = e.target.value; }

  @action async submitDispute() {
    if (!this.disputeReason.trim()) { this.error = "请填写争议原因"; return; }
    this.disputing = true; this.error = null;
    try {
      await ajax("/credit/product/dispute.json", {
        type: "POST",
        data: { order_id: this.disputeOrderId, reason: this.disputeReason },
      });
      this.disputeOrderId = null;
      this.disputeReason = "";
      await this.loadOrders();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "提交失败";
    } finally { this.disputing = false; }
  }

  @action stopPropagation(e) { e.stopPropagation(); }

  <template>
    <div class="credit-wallet-page">
      <h2>{{icon "cart-shopping"}} 我的购买</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.orders.length}}
        <div class="credit-orders-list">
          {{#each this.orders as |o|}}
            <div class="seller-order-row">
              <div class="order-info">
                <span class="order-name">{{o.order_name}}</span>
                <span class="order-meta">卖家: @{{o.seller_username}} · {{o.order_no}}</span>
              </div>
              <div class="order-amount">{{o.amount}} 积分</div>
              <div class="order-delivery-status">
                {{#if (eq o.delivery_status "pending_delivery")}}
                  <span style="color: var(--tertiary); font-weight: 600;">待发货</span>
                {{else if (eq o.delivery_status "processing")}}
                  <span style="color: #d97706; font-weight: 600;">充值中</span>
                {{else if (eq o.delivery_status "delivered")}}
                  <span style="color: var(--success); font-weight: 600;">已发货</span>
                {{else if (eq o.delivery_status "refunded")}}
                  <span style="color: var(--danger); font-weight: 600;">已退款</span>
                {{else}}
                  <span style="color: var(--success); font-weight: 600;">已完成</span>
                {{/if}}
              </div>
              <div class="order-actions" style="display: flex; gap: 4px;">
                {{#if o.delivery_status}}
                  {{#if (not o.has_dispute)}}
                    {{#if (not (eq o.delivery_status "refunded"))}}
                      <button class="btn btn-small btn-danger" type="button" {{on "click" (fn this.openDispute o.id)}}>申请争议</button>
                    {{/if}}
                  {{else}}
                    <span style="font-size: 0.85em; color: var(--danger); font-weight: 500;">
                      {{#if (eq o.dispute_status "disputing")}}争议处理中{{else if (eq o.dispute_status "resolved")}}已退款{{else if (eq o.dispute_status "rejected")}}争议被拒绝{{else if (eq o.dispute_status "auto_refunded")}}已自动退款{{else}}{{o.dispute_status}}{{/if}}
                    </span>
                  {{/if}}
                {{/if}}
              </div>
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="no-data-text">暂无购买记录</p>
      {{/if}}

      {{#if this.disputeOrderId}}
        <div class="credit-modal-overlay" {{on "click" this.cancelDispute}}>
          <div class="credit-modal" role="dialog" {{on "click" this.stopPropagation}}>
            <h3>申请争议</h3>
            <p style="font-size: 0.85em; color: var(--primary-medium);">卖家需在48小时内处理，超时将自动退款并额外补偿。</p>
            {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}
            <div class="form-row">
              <label>争议原因</label>
              <textarea rows="3" placeholder="请描述您的问题..." {{on "input" this.updateDisputeReason}}>{{this.disputeReason}}</textarea>
            </div>
            <div class="credit-modal-actions">
              <button class="btn btn-default" type="button" {{on "click" this.cancelDispute}}>取消</button>
              <button class="btn btn-danger" type="button" disabled={{this.disputing}} {{on "click" this.submitDispute}}>
                {{if this.disputing "提交中..." "提交争议"}}
              </button>
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditMyOrdersPage /></template>);
