import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

class CreditMerchantPage extends Component {
  @tracked apps = [];
  @tracked loading = true;
  @tracked showCreate = false;
  @tracked newAppName = "";
  @tracked newNotifyUrl = "";
  @tracked newDescription = "";
  @tracked creating = false;
  @tracked error = null;
  @tracked expandedAppId = null;
  @tracked products = [];
  @tracked productsLoading = false;
  @tracked showProductForm = false;
  @tracked productName = "";
  @tracked productPrice = "";
  @tracked productDesc = "";
  @tracked productStock = "-1";
  @tracked productLimit = "0";
  @tracked productSaving = false;

  constructor() {
    super(...arguments);
    this.loadApps();
  }

  async loadApps() {
    try {
      const data = await ajax("/credit/merchant/apps.json");
      this.apps = data.apps || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  @action toggleCreate() { this.showCreate = !this.showCreate; this.error = null; }
  @action updateNewAppName(e) { this.newAppName = e.target.value; }
  @action updateNewNotifyUrl(e) { this.newNotifyUrl = e.target.value; }
  @action updateNewDescription(e) { this.newDescription = e.target.value; }

  @action async createApp() {
    if (!this.newAppName) { this.error = "请输入应用名称"; return; }
    this.creating = true;
    this.error = null;
    try {
      await ajax("/credit/merchant/apps.json", {
        type: "POST",
        data: { name: this.newAppName, notify_url: this.newNotifyUrl, description: this.newDescription },
      });
      this.showCreate = false;
      this.newAppName = "";
      this.newNotifyUrl = "";
      this.newDescription = "";
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally {
      this.creating = false;
    }
  }

  @action toggleExpand(appId) {
    if (this.expandedAppId === appId) {
      this.expandedAppId = null;
      this.products = [];
    } else {
      this.expandedAppId = appId;
      this.loadProducts(appId);
    }
    this.showProductForm = false;
  }

  async loadProducts(appId) {
    this.productsLoading = true;
    try {
      const data = await ajax(`/credit/merchant/${appId}/products.json`);
      this.products = data.products || [];
    } catch (_) { /* ignore */ }
    finally { this.productsLoading = false; }
  }

  @action toggleProductForm() { this.showProductForm = !this.showProductForm; }
  @action updateProductName(e) { this.productName = e.target.value; }
  @action updateProductPrice(e) { this.productPrice = e.target.value; }
  @action updateProductDesc(e) { this.productDesc = e.target.value; }
  @action updateProductStock(e) { this.productStock = e.target.value; }
  @action updateProductLimit(e) { this.productLimit = e.target.value; }

  @action async saveProduct() {
    if (!this.productName || !this.productPrice) { this.error = "请填写商品名和价格"; return; }
    this.productSaving = true;
    this.error = null;
    try {
      await ajax(`/credit/merchant/${this.expandedAppId}/products.json`, {
        type: "POST",
        data: {
          name: this.productName,
          price: this.productPrice,
          description: this.productDesc,
          stock: this.productStock,
          limit_per_user: this.productLimit,
        },
      });
      this.showProductForm = false;
      this.productName = "";
      this.productPrice = "";
      this.productDesc = "";
      this.productStock = "-1";
      this.productLimit = "0";
      await this.loadProducts(this.expandedAppId);
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally {
      this.productSaving = false;
    }
  }

  @action async toggleProductStatus(productId, currentStatus) {
    try {
      await ajax(`/credit/merchant/${this.expandedAppId}/products/${productId}.json`, {
        type: "PUT",
        data: { status: currentStatus ? "inactive" : "active" },
      });
      await this.loadProducts(this.expandedAppId);
    } catch (_) { /* ignore */ }
  }

  <template>
    <div class="credit-merchant-page">
      <h2>🏪 商户中心</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">← 返回钱包</a>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      <button class="btn btn-primary btn-small" type="button" {{on "click" this.toggleCreate}}>
        {{if this.showCreate "取消" "创建应用"}}
      </button>

      {{#if this.showCreate}}
        <div class="credit-form-card">
          <div class="form-row"><label>应用名称</label><input type="text" value={{this.newAppName}} placeholder="输入应用名称" {{on "input" this.updateNewAppName}} /></div>
          <div class="form-row"><label>回调地址</label><input type="text" value={{this.newNotifyUrl}} placeholder="https://..." {{on "input" this.updateNewNotifyUrl}} /></div>
          <div class="form-row"><label>描述</label><textarea maxlength="200" placeholder="应用描述" {{on "input" this.updateNewDescription}}>{{this.newDescription}}</textarea></div>
          <button class="btn btn-primary" type="button" disabled={{this.creating}} {{on "click" this.createApp}}>
            {{if this.creating "创建中..." "确认创建"}}
          </button>
        </div>
      {{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.apps.length}}
        <div class="credit-apps-list">
          {{#each this.apps as |app|}}
            <div class="app-card">
              <div class="app-header" role="button" {{on "click" (fn this.toggleExpand app.id)}}>
                <span class="app-name">{{app.name}}</span>
                <span class="app-status {{if app.active 'active' 'inactive'}}">{{if app.active "启用" "停用"}}</span>
              </div>
              {{#if (eq this.expandedAppId app.id)}}
                <div class="app-detail">
                  <div class="app-info">
                    <div class="info-row"><span class="info-label">App ID</span><span class="info-value">{{app.app_id}}</span></div>
                    <div class="info-row"><span class="info-label">App Secret</span><span class="info-value secret">{{app.app_secret}}</span></div>
                    {{#if app.notify_url}}<div class="info-row"><span class="info-label">回调地址</span><span class="info-value">{{app.notify_url}}</span></div>{{/if}}
                    {{#if app.description}}<div class="info-row"><span class="info-label">描述</span><span class="info-value">{{app.description}}</span></div>{{/if}}
                  </div>

                  <h4>商品列表</h4>
                  <button class="btn btn-small btn-default" type="button" {{on "click" this.toggleProductForm}}>
                    {{if this.showProductForm "取消" "添加商品"}}
                  </button>

                  {{#if this.showProductForm}}
                    <div class="credit-form-card product-form">
                      <div class="form-row"><label>商品名</label><input type="text" value={{this.productName}} {{on "input" this.updateProductName}} /></div>
                      <div class="form-row"><label>价格</label><input type="number" min="0.01" step="0.01" value={{this.productPrice}} {{on "input" this.updateProductPrice}} /></div>
                      <div class="form-row"><label>描述</label><input type="text" value={{this.productDesc}} {{on "input" this.updateProductDesc}} /></div>
                      <div class="form-row"><label>库存(-1无限)</label><input type="number" value={{this.productStock}} {{on "input" this.updateProductStock}} /></div>
                      <div class="form-row"><label>限购(0不限)</label><input type="number" min="0" value={{this.productLimit}} {{on "input" this.updateProductLimit}} /></div>
                      <button class="btn btn-primary btn-small" type="button" disabled={{this.productSaving}} {{on "click" this.saveProduct}}>
                        {{if this.productSaving "保存中..." "保存"}}
                      </button>
                    </div>
                  {{/if}}

                  {{#if this.productsLoading}}
                    <p class="loading-text">加载商品...</p>
                  {{else if this.products.length}}
                    <div class="products-list">
                      {{#each this.products as |p|}}
                        <div class="product-row">
                          <span class="product-name">{{p.name}}</span>
                          <span class="product-price">{{p.price}} 积分</span>
                          <span class="product-stock">库存: {{if (eq p.stock -1) "无限" p.stock}}</span>
                          <span class="product-sold">已售: {{p.sold_count}}</span>
                          <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.toggleProductStatus p.id p.active)}}>
                            {{if p.active "下架" "上架"}}
                          </button>
                        </div>
                      {{/each}}
                    </div>
                  {{else}}
                    <p class="no-data-text">暂无商品</p>
                  {{/if}}
                </div>
              {{/if}}
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="no-data-text">暂无商户应用，点击上方按钮创建</p>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditMerchantPage /></template>);
