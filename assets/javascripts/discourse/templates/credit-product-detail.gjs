import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { helper } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const stockLabel = helper(function stockLabel([stock]) { return stock === -1 ? "无限" : String(stock); });

class CreditProductDetailPage extends Component {
  @tracked product = null;
  @tracked loading = true;
  @tracked error = null;
  @tracked payKey = "";
  @tracked buying = false;
  @tracked buySuccess = false;

  constructor() {
    super(...arguments);
    this.loadProduct();
  }

  get productId() {
    const match = window.location.pathname.match(/\/credit\/product\/(\d+)/);
    return match ? match[1] : null;
  }

  async loadProduct() {
    try {
      const data = await ajax(`/credit/product/${this.productId}.json`);
      this.product = data.product;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally {
      this.loading = false;
    }
  }

  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async buyProduct() {
    if (!this.payKey) { this.error = "请输入支付密码"; return; }
    this.buying = true;
    this.error = null;
    try {
      await ajax(`/credit/product/${this.productId}/buy.json`, {
        type: "POST",
        data: { pay_key: this.payKey },
      });
      this.buySuccess = true;
      this.payKey = "";
      await this.loadProduct();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "购买失败";
    } finally {
      this.buying = false;
    }
  }

  <template>
    <div class="credit-product-detail-page">
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">← 返回</a>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{else if this.product}}
        <div class="product-detail-card">
          <h2>{{this.product.name}}</h2>
          {{#if this.product.merchant_name}}
            <p class="product-merchant">商户: {{this.product.merchant_name}}</p>
          {{/if}}
          {{#if this.product.description}}
            <p class="product-description">{{this.product.description}}</p>
          {{/if}}
          <div class="product-info-grid">
            <div class="info-item"><span class="info-label">价格</span><span class="info-value price">{{this.product.price}} 积分</span></div>
            <div class="info-item"><span class="info-label">库存</span><span class="info-value">{{stockLabel this.product.stock}}</span></div>
            <div class="info-item"><span class="info-label">已售</span><span class="info-value">{{this.product.sold_count}}</span></div>
            {{#if this.product.limit_per_user}}
              <div class="info-item"><span class="info-label">限购</span><span class="info-value">{{this.product.limit_per_user}} 件</span></div>
            {{/if}}
          </div>

          {{#if this.buySuccess}}
            <div class="credit-success">🎉 购买成功！</div>
          {{/if}}

          <div class="product-buy-section">
            <div class="form-row">
              <label>支付密码</label>
              <input type="password" maxlength="6" value={{this.payKey}} placeholder="6位数字密码" {{on "input" this.updatePayKey}} />
            </div>
            <button class="btn btn-primary" type="button" disabled={{this.buying}} {{on "click" this.buyProduct}}>
              {{if this.buying "购买中..." "💰 立即购买"}}
            </button>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditProductDetailPage /></template>);
