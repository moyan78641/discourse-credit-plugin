import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

class CreditDisputesPage extends Component {
  @tracked tab = "mine";
  @tracked disputes = [];
  @tracked loading = true;
  @tracked error = null;
  @tracked showCreate = false;
  @tracked disputableOrders = [];
  @tracked disputableLoading = false;
  @tracked selectedOrderId = "";
  @tracked newReason = "";
  @tracked creating = false;
  @tracked reviewId = null;
  @tracked reviewReason = "";
  @tracked reviewing = false;

  constructor() {
    super(...arguments);
    this.loadDisputes();
  }

  get isMineTab() { return this.tab === "mine"; }

  @action switchTab(t) {
    this.tab = t;
    this.loadDisputes();
  }

  async loadDisputes() {
    this.loading = true;
    this.error = null;
    try {
      const url = this.tab === "merchant" ? "/credit/disputes/merchant.json" : "/credit/disputes.json";
      const data = await ajax(url, { type: "POST", data: {} });
      this.disputes = data.disputes || [];
    } catch (_) { this.disputes = []; }
    finally { this.loading = false; }
  }

  @action async toggleCreate() {
    this.showCreate = !this.showCreate;
    if (this.showCreate && this.disputableOrders.length === 0) {
      this.disputableLoading = true;
      try {
        const data = await ajax("/credit/disputable-orders.json");
        this.disputableOrders = data.orders || [];
      } catch (_) { this.disputableOrders = []; }
      finally { this.disputableLoading = false; }
    }
  }

  @action updateSelectedOrder(e) { this.selectedOrderId = e.target.value; }
  @action updateNewReason(e) { this.newReason = e.target.value; }

  @action async createDispute() {
    if (!this.selectedOrderId || !this.newReason) { this.error = "请选择订单并填写原因"; return; }
    this.creating = true;
    this.error = null;
    try {
      await ajax("/credit/dispute.json", {
        type: "POST",
        data: { order_id: this.selectedOrderId, reason: this.newReason },
      });
      this.showCreate = false;
      this.selectedOrderId = "";
      this.newReason = "";
      this.disputableOrders = [];
      await this.loadDisputes();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "发起失败";
    } finally {
      this.creating = false;
    }
  }

  @action startReview(id) { this.reviewId = id; this.reviewReason = ""; }
  @action updateReviewReason(e) { this.reviewReason = e.target.value; }

  @action async doReview(status) {
    this.reviewing = true;
    this.error = null;
    try {
      await ajax("/credit/dispute/review.json", {
        type: "POST",
        data: { dispute_id: this.reviewId, status, reason: this.reviewReason },
      });
      this.reviewId = null;
      await this.loadDisputes();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "处理失败";
    } finally {
      this.reviewing = false;
    }
  }

  @action async closeDispute(id) {
    if (!confirm("确定撤销该争议？")) return;
    try {
      await ajax("/credit/dispute/close.json", { type: "POST", data: { dispute_id: id } });
      await this.loadDisputes();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "关闭失败";
    }
  }

  <template>
    <div class="credit-disputes-page">
      <h2>{{icon "gavel"}} 争议管理</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      <div class="credit-tabs">
        <button class="btn {{if this.isMineTab 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "mine")}}>我发起的</button>
        <button class="btn {{if this.isMineTab 'btn-default' 'btn-primary'}}" type="button" {{on "click" (fn this.switchTab "merchant")}}>我收到的</button>
      </div>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      <button class="btn btn-primary btn-small" type="button" {{on "click" this.toggleCreate}}>
        {{if this.showCreate "取消" "发起争议"}}
      </button>

      {{#if this.showCreate}}
        <div class="credit-form-card">
          <div class="form-row">
            <label>选择订单</label>
            {{#if this.disputableLoading}}
              <p class="loading-text">加载可争议订单...</p>
            {{else if this.disputableOrders.length}}
              <select class="order-type-select" {{on "change" this.updateSelectedOrder}}>
                <option value="">-- 请选择订单 --</option>
                {{#each this.disputableOrders as |o|}}
                  <option value={{o.id}}>#{{o.id}} {{o.order_name}} ({{o.amount}}积分 → {{o.payee_username}})</option>
                {{/each}}
              </select>
            {{else}}
              <p class="no-data-text">暂无可争议的订单（仅支付/转账成功且在争议时间窗口内的订单可发起争议）</p>
            {{/if}}
          </div>
          <div class="form-row"><label>争议原因</label><textarea maxlength="500" placeholder="请描述争议原因" {{on "input" this.updateNewReason}}>{{this.newReason}}</textarea></div>
          <button class="btn btn-primary" type="button" disabled={{this.creating}} {{on "click" this.createDispute}}>
            {{if this.creating "提交中..." "提交争议"}}
          </button>
        </div>
      {{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.disputes.length}}
        <div class="credit-disputes-list">
          {{#each this.disputes as |d|}}
            <div class="dispute-card {{d.status}}">
              <div class="dispute-header">
                <span class="dispute-order">订单 #{{d.order_id}} · {{d.order_name}}</span>
                <span class="dispute-status">{{d.status}}</span>
              </div>
              <div class="dispute-body">
                <p class="dispute-reason">{{d.reason}}</p>
                <div class="dispute-meta">
                  <span>金额: {{d.amount}}</span>
                  <span>发起人: {{d.initiator_username}}</span>
                  <span>商家: {{d.payee_username}}</span>
                  {{#if d.handler_username}}<span>处理人: {{d.handler_username}}</span>{{/if}}
                </div>
              </div>
              <div class="dispute-actions">
                {{#if (eq d.status "disputing")}}
                  {{#if this.isMineTab}}
                    <button class="btn btn-small btn-default" type="button" {{on "click" (fn this.closeDispute d.id)}}>撤销</button>
                  {{else}}
                    <button class="btn btn-small btn-primary" type="button" {{on "click" (fn this.startReview d.id)}}>审核</button>
                  {{/if}}
                {{/if}}
              </div>

              {{#if (eq this.reviewId d.id)}}
                <div class="dispute-review-form">
                  <div class="form-row"><label>理由（拒绝时必填）</label><input type="text" value={{this.reviewReason}} {{on "input" this.updateReviewReason}} /></div>
                  <div class="review-actions">
                    <button class="btn btn-small btn-primary" type="button" disabled={{this.reviewing}} {{on "click" (fn this.doReview "refund")}}>同意退款</button>
                    <button class="btn btn-small btn-danger" type="button" disabled={{this.reviewing}} {{on "click" (fn this.doReview "closed")}}>拒绝</button>
                  </div>
                </div>
              {{/if}}
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="no-data-text">暂无争议记录</p>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditDisputesPage /></template>);
