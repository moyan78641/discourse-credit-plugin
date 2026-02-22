import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

class CreditPayPage extends Component {
  @tracked order = null;
  @tracked merchant = null;
  @tracked loading = true;
  @tracked error = null;
  @tracked payKey = "";
  @tracked paying = false;
  @tracked paySuccess = false;
  @tracked returnUrl = null;

  constructor() {
    super(...arguments);
    this.loadOrder();
  }

  get orderId() {
    const params = new URLSearchParams(window.location.search);
    return params.get("order_id");
  }

  async loadOrder() {
    if (!this.orderId) { this.error = "缺少订单ID"; this.loading = false; return; }
    try {
      const data = await ajax(`/credit/pay/order.json?order_id=${this.orderId}`);
      this.order = data.order;
      this.merchant = data.merchant;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "订单加载失败";
    } finally {
      this.loading = false;
    }
  }

  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async confirmPay() {
    if (!this.payKey) { this.error = "请输入支付密码"; return; }
    this.paying = true;
    this.error = null;
    try {
      const data = await ajax("/credit/pay/confirm.json", {
        type: "POST",
        data: { order_id: this.orderId, pay_key: this.payKey },
      });
      this.paySuccess = true;
      this.returnUrl = data.return_url;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "支付失败";
    } finally {
      this.paying = false;
    }
  }

  <template>
    <div class="credit-pay-page">
      <h2>{{icon "shopping-cart"}} 收银台</h2>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.paySuccess}}
        <div class="pay-success-card">
          <h3>{{icon "check"}} 支付成功</h3>
          {{#if this.returnUrl}}
            <a href={{this.returnUrl}} class="btn btn-primary">返回商户</a>
          {{else}}
            <a href="/credit" class="btn btn-default">返回钱包</a>
          {{/if}}
        </div>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
        <a href="/credit" class="btn btn-default">返回钱包</a>
      {{else if this.order}}
        <div class="pay-order-card">
          <div class="pay-merchant">商户: {{this.merchant.name}}</div>
          <div class="pay-order-name">{{this.order.name}}</div>
          <div class="pay-amount">{{this.order.amount}} <span class="unit">积分</span></div>
          <div class="form-row">
            <label>支付密码</label>
            <input type="password" maxlength="6" value={{this.payKey}} placeholder="6位数字密码" {{on "input" this.updatePayKey}} />
          </div>
          <button class="btn btn-primary btn-large" type="button" disabled={{this.paying}} {{on "click" this.confirmPay}}>
            {{if this.paying "支付中..." "确认支付"}}
          </button>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditPayPage /></template>);
