import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

class CreditPaymentPage extends Component {
  @service currentUser;
  @service router;

  @tracked txn = null;
  @tracked loading = true;
  @tracked error = null;
  @tracked payKey = "";
  @tracked paying = false;
  @tracked success = false;
  @tracked callbackUrl = null;

  constructor() {
    super(...arguments);
    this.loadTransaction();
  }

  get transactionId() {
    return this.args.model?.transaction_id || window.location.pathname.split("/").pop();
  }

  get txnCompleted() {
    return this.txn && this.txn.status === "completed";
  }

  get isTest() {
    return this.txn && this.txn.is_test;
  }

  async loadTransaction() {
    try {
      const data = await ajax(`/credit/payment/pay/${this.transactionId}.json`);
      this.txn = data;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "交易不存在";
    } finally {
      this.loading = false;
    }
  }

  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async confirmPay() {
    if (!this.payKey || this.payKey.length !== 6) {
      this.error = "请输入6位支付密码";
      return;
    }
    this.paying = true;
    this.error = null;
    try {
      const result = await ajax(`/credit/payment/confirm/${this.transactionId}.json`, {
        type: "POST",
        data: { pay_key: this.payKey },
      });
      this.success = true;
      this.callbackUrl = result.callback_url;
      // 3秒后自动跳转
      if (this.callbackUrl) {
        setTimeout(() => { window.location.href = this.callbackUrl; }, 3000);
      }
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "支付失败";
    } finally {
      this.paying = false;
    }
  }

  <template>
    <div class="credit-payment-page">
      {{#if this.loading}}
        <div class="payment-loading">
          <p class="loading-text">加载交易信息...</p>
        </div>
      {{else if this.success}}
        <div class="payment-success-card">
          <div class="success-icon">{{icon "check"}}</div>
          {{#if this.isTest}}
            <div class="payment-test-badge">{{icon "bolt-lightning"}} 测试交易</div>
          {{/if}}
          <h2>支付成功</h2>
          <p>已支付 <span class="amount-highlight">{{this.txn.amount}}</span> 积分</p>
          <p class="payment-desc">{{this.txn.description}}</p>
          {{#if this.callbackUrl}}
            <p class="redirect-hint">正在跳转回商户页面...</p>
            <a href={{this.callbackUrl}} class="btn btn-primary">立即跳转</a>
          {{else}}
            <a href="/credit" class="btn btn-primary">返回钱包</a>
          {{/if}}
        </div>
      {{else if this.error}}
        {{#unless this.txn}}
          <div class="payment-error-card">
            <div class="error-icon">{{icon "xmark"}}</div>
            <h2>交易异常</h2>
            <p>{{this.error}}</p>
            <a href="/credit" class="btn btn-default">返回钱包</a>
          </div>
        {{/unless}}
      {{/if}}

      {{#if this.txn}}
        {{#unless this.success}}
          {{#if this.txn.expired}}
            <div class="payment-error-card">
              <div class="error-icon">{{icon "xmark"}}</div>
              <h2>交易已过期</h2>
              <p>请返回商户重新发起支付</p>
            </div>
          {{else if this.txnCompleted}}
            <div class="payment-success-card">
              <div class="success-icon">{{icon "check"}}</div>
              <h2>该交易已完成</h2>
            </div>
          {{else}}
            <div class="payment-confirm-card">
              {{#if this.isTest}}
                <div class="payment-test-badge">{{icon "bolt-lightning"}} 测试模式 — 不会产生实际扣款</div>
              {{/if}}
              <div class="payment-app-name">
                {{icon "store"}} {{this.txn.app_name}}
              </div>
              <div class="payment-amount-display">
                <span class="payment-amount-label">支付金额</span>
                <span class="payment-amount-value">{{this.txn.amount}} <small>积分</small></span>
              </div>
              <div class="payment-detail-rows">
                <div class="payment-detail-row">
                  <span>交易描述</span>
                  <span>{{this.txn.description}}</span>
                </div>
                {{#if this.txn.platform_fee}}
                  <div class="payment-detail-row fee">
                    <span>平台手续费</span>
                    <span>{{this.txn.platform_fee}} 积分</span>
                  </div>
                {{/if}}
              </div>

              {{#if this.currentUser}}
                {{#if this.error}}
                  <div class="credit-error">{{this.error}}</div>
                {{/if}}
                <div class="payment-pay-form">
                  <div class="form-row">
                    <label>支付密码</label>
                    <input
                      type="password"
                      maxlength="6"
                      placeholder="请输入6位数字支付密码"
                      value={{this.payKey}}
                      {{on "input" this.updatePayKey}}
                    />
                  </div>
                  <button
                    class="btn btn-primary btn-large payment-confirm-btn"
                    type="button"
                    disabled={{this.paying}}
                    {{on "click" this.confirmPay}}
                  >
                    {{if this.paying "支付中..." "确认支付"}}
                  </button>
                </div>
              {{else}}
                <div class="payment-login-hint">
                  <p>请先登录后再完成支付</p>
                  <a href="/login" class="btn btn-primary">登录</a>
                </div>
              {{/if}}
            </div>
          {{/if}}
        {{/unless}}
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(
  <template><CreditPaymentPage @model={{@model}} /></template>
);
