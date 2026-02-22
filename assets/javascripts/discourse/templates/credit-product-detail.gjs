import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

class CreditProductDetailPage extends Component {
  @tracked product = null;
  @tracked loading = true;
  @tracked error = null;
  @tracked payKey = "";
  @tracked buying = false;
  @tracked buyResult = null;

  constructor() {
    super(...arguments);
    this.loadProduct();
  }

  get productId() {
    const m = this.args.model;
    if (m?.id) return m.id;
    if (m?.params?.id) return m.params.id;
    // URL fallback
    const match = window.location.pathname.match(/\/credit\/product\/(\d+)/);
    return match ? match[1] : null;
  }

  async loadProduct() {
    try {
      const data = await ajax(`/credit/product/${this.productId}.json`);
      this.product = data;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally {
      this.loading = false;
    }
  }

  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async buyProduct() {
    if (!this.payKey) { this.error = "请输入支付密码"; return; }
    this.buying = true; this.error = null;
    try {
      const result = await ajax(`/credit/product/${this.productId}/buy.json`, {
        type: "POST", data: { pay_key: this.payKey },
      });
      this.buyResult = result;
      this.payKey = "";
      await this.loadProduct();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "购买失败";
    } finally { this.buying = false; }
  }

  <template>
    <div class="credit-product-detail-page">
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回</a>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{else if this.product}}
        <div class="product-detail-card">
          <h2>{{this.product.name}}</h2>
          <p class="product-merchant">卖家: @{{this.product.owner_username}}</p>
          {{#if this.product.description}}<p class="product-description">{{this.product.description}}</p>{{/if}}
          <div class="product-info-grid">
            <div class="info-item"><span class="info-label">价格</span><span class="info-value price">{{this.product.price}} 积分</span></div>
            <div class="info-item"><span class="info-label">库存</span><span class="info-value">{{if (eq this.product.stock -1) "无限" this.product.stock}}</span></div>
            <div class="info-item"><span class="info-label">已售</span><span class="info-value">{{this.product.sold_count}}</span></div>
            {{#if this.product.auto_delivery}}<div class="info-item"><span class="info-label">发货方式</span><span class="info-value">自动发货（站内信）</span></div>{{/if}}
          </div>

          {{#if this.buyResult}}
            <div class="credit-success">
              {{icon "check"}} 购买成功！订单号: {{this.buyResult.order_no}}
              {{#if this.buyResult.auto_delivery}}
                <br />卡密已通过站内信发送，请查收。
              {{/if}}
            </div>
          {{/if}}

          {{#if this.product.in_stock}}
            <div class="product-buy-section">
              <div class="form-row">
                <label>支付密码</label>
                <input type="password" maxlength="6" value={{this.payKey}} placeholder="6位数字密码" {{on "input" this.updatePayKey}} />
              </div>
              <button class="btn btn-primary" type="button" disabled={{this.buying}} {{on "click" this.buyProduct}}>
                {{if this.buying "购买中..." "立即购买"}}
              </button>
            </div>
          {{else}}
            <div class="credit-error">商品已售罄</div>
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditProductDetailPage @model={{@model}} /></template>);
