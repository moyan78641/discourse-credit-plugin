import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { eq, not } from "truth-helpers";
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
    const match = window.location.pathname.match(/\/credit\/product\/(\d+)/);
    if (match) return match[1];
    const m = this.args.model;
    if (m?.id) return m.id;
    if (m?.params?.id) return m.params.id;
    return null;
  }

  get stockText() {
    const p = this.product;
    if (!p) return "0";
    if (p.stock === -1) return "无限";
    if (p.stock === null || p.stock === undefined) return "0";
    return String(p.stock);
  }

  get priceText() {
    const p = this.product;
    if (!p || !p.price) return "0";
    return String(p.price);
  }

  get soldText() {
    const p = this.product;
    if (!p) return "0";
    return String(p.sold_count || 0);
  }

  get isSoldOut() {
    const p = this.product;
    if (!p) return true;
    return p.in_stock === false;
  }

  async loadProduct() {
    const pid = this.productId;
    if (!pid) { this.error = "商品ID无效"; this.loading = false; return; }
    try {
      const data = await ajax(`/credit/product/${pid}.json`);
      this.product = data;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally { this.loading = false; }
  }

  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async buyProduct() {
    if (!this.payKey) { this.error = "请输入支付密码"; return; }
    this.buying = true; this.error = null; this.buyResult = null;
    try {
      const data = await ajax(`/credit/product/${this.product.id}/buy.json`, {
        type: "POST",
        data: { pay_key: this.payKey },
      });
      this.buyResult = data;
      this.payKey = "";
      await this.loadProduct();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "购买失败";
    } finally { this.buying = false; }
  }

  <template>
    <div class="credit-product-detail-page">
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      {{#if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{/if}}

      {{#if this.buyResult}}
        <div class="credit-success">
          购买成功！订单号: {{this.buyResult.order_no}}
          {{#if this.buyResult.auto_delivery}}
            （卡密已通过站内信发送）
          {{/if}}
        </div>
      {{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.product}}
        <div class="product-detail-card">
          <h2>{{this.product.name}}</h2>

          {{#if this.product.description}}
            <p class="product-description">{{this.product.description}}</p>
          {{/if}}

          <div class="product-info-grid">
            <div class="info-row">
              <span class="info-label">卖家</span>
              <span class="info-value">@{{this.product.owner_username}}</span>
            </div>
            <div class="info-row">
              <span class="info-label">价格</span>
              <span class="info-value" style="color: var(--tertiary); font-size: 1.2em; font-weight: 700;">{{this.priceText}} 积分</span>
            </div>
            <div class="info-row">
              <span class="info-label">库存</span>
              <span class="info-value">{{this.stockText}}</span>
            </div>
            <div class="info-row">
              <span class="info-label">已售</span>
              <span class="info-value">{{this.soldText}}</span>
            </div>
          </div>

          {{#if this.isSoldOut}}
            <div style="text-align: center; padding: 16px; color: var(--danger); font-weight: 600; font-size: 1.1em;">
              商品已售罄
            </div>
          {{else if (not (eq this.product.status "active"))}}
            <div style="text-align: center; padding: 16px; color: var(--danger); font-weight: 600;">
              商品已下架
            </div>
          {{else}}
            <div class="product-buy-section">
              <div class="form-row">
                <label>支付密码</label>
                <input type="password" value={{this.payKey}} placeholder="请输入支付密码" {{on "input" this.updatePayKey}} />
              </div>
              <button class="btn btn-primary" type="button" disabled={{this.buying}} {{on "click" this.buyProduct}}>
                {{if this.buying "购买中..." "立即购买"}}
              </button>
            </div>
          {{/if}}
        </div>
      {{else}}
        <p class="no-data-text">商品不存在</p>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditProductDetailPage /></template>);
