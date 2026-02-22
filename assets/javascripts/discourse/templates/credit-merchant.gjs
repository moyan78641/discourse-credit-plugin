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

class CreditMerchantPage extends Component {
  @tracked apps = [];
  @tracked loading = true;
  @tracked showCreate = false;
  @tracked newAppName = "";
  @tracked newRedirectUri = "";
  @tracked newNotifyUrl = "";
  @tracked newDescription = "";
  @tracked creating = false;
  @tracked createdApp = null;
  @tracked error = null;
  @tracked expandedAppId = null;
  @tracked editingAppId = null;
  @tracked editFields = {};
  @tracked editSaving = false;
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

  @action toggleCreate() { this.showCreate = !this.showCreate; this.createdApp = null; this.error = null; }
  @action updateNewAppName(e) { this.newAppName = e.target.value; }
  @action updateNewRedirectUri(e) { this.newRedirectUri = e.target.value; }
  @action updateNewNotifyUrl(e) { this.newNotifyUrl = e.target.value; }
  @action updateNewDescription(e) { this.newDescription = e.target.value; }

  @action async createApp() {
    if (!this.newAppName) { this.error = "请输入应用名称"; return; }
    this.creating = true;
    this.error = null;
    try {
      const data = await ajax("/credit/merchant/apps.json", {
        type: "POST",
        data: {
          name: this.newAppName,
          redirect_uri: this.newRedirectUri,
          notify_url: this.newNotifyUrl,
          description: this.newDescription,
        },
      });
      this.createdApp = data.app;
      this.showCreate = false;
      this.newAppName = "";
      this.newRedirectUri = "";
      this.newNotifyUrl = "";
      this.newDescription = "";
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally {
      this.creating = false;
    }
  }

  @action dismissCreated() { this.createdApp = null; }

  @action toggleExpand(appId) {
    if (this.expandedAppId === appId) {
      this.expandedAppId = null;
      this.products = [];
      this.editingAppId = null;
    } else {
      this.expandedAppId = appId;
      this.editingAppId = null;
      this.loadProducts(appId);
    }
    this.showProductForm = false;
  }

  @action startEditApp(app) {
    this.editingAppId = app.id;
    this.editFields = {
      app_name: app.app_name,
      redirect_uri: app.redirect_uri || "",
      notify_url: app.notify_url || "",
      description: app.description || "",
    };
  }

  @action updateEditField(field, e) {
    this.editFields = { ...this.editFields, [field]: e.target.value };
  }

  @action cancelEditApp() { this.editingAppId = null; }

  @action async saveEditApp() {
    this.editSaving = true;
    this.error = null;
    try {
      await ajax(`/credit/merchant/apps/${this.editingAppId}.json`, {
        type: "PUT",
        data: {
          name: this.editFields.app_name,
          redirect_uri: this.editFields.redirect_uri,
          notify_url: this.editFields.notify_url,
          description: this.editFields.description,
        },
      });
      this.editingAppId = null;
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "保存失败";
    } finally {
      this.editSaving = false;
    }
  }

  @action async toggleAppStatus(app) {
    try {
      await ajax(`/credit/merchant/apps/${app.id}.json`, {
        type: "PUT",
        data: { is_active: !app.is_active },
      });
      await this.loadApps();
    } catch (_) { /* ignore */ }
  }

  @action async resetSecret(appId) {
    if (!confirm("重置密钥后旧密钥立即失效，确定继续？")) return;
    try {
      const data = await ajax(`/credit/merchant/apps/${appId}/reset-secret.json`, { type: "POST" });
      this.createdApp = data.app;
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "重置失败";
    }
  }

  @action copyText(text) {
    navigator.clipboard.writeText(text);
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
          name: this.productName, price: this.productPrice,
          description: this.productDesc, stock: this.productStock,
          limit_per_user: this.productLimit,
        },
      });
      this.showProductForm = false;
      this.productName = ""; this.productPrice = ""; this.productDesc = "";
      this.productStock = "-1"; this.productLimit = "0";
      await this.loadProducts(this.expandedAppId);
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally { this.productSaving = false; }
  }

  @action async toggleProductStatus(productId, isActive) {
    try {
      await ajax(`/credit/merchant/${this.expandedAppId}/products/${productId}.json`, {
        type: "PUT",
        data: { status: isActive ? "inactive" : "active" },
      });
      await this.loadProducts(this.expandedAppId);
    } catch (_) { /* ignore */ }
  }

  <template>
    <div class="credit-merchant-page">
      <h2>{{icon "store"}} 商户中心</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      {{!-- 创建成功后显示凭证 --}}
      {{#if this.createdApp}}
        <div class="merchant-credential-notice">
          <h3>{{icon "check"}} 应用凭证（请妥善保存，密钥仅显示一次）</h3>
          <div class="credential-row">
            <span class="credential-label">商户ID (pid)</span>
            <code class="credential-value">{{this.createdApp.client_id}}</code>
            <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText this.createdApp.client_id)}}>复制</button>
          </div>
          <div class="credential-row">
            <span class="credential-label">商户密钥 (key)</span>
            <code class="credential-value">{{this.createdApp.client_secret}}</code>
            <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText this.createdApp.client_secret)}}>复制</button>
          </div>
          <div class="credential-tip">
            <p>易支付接口地址：</p>
            <div class="credential-row">
              <span class="credential-label">提交地址</span>
              <code class="credential-value">/credit-pay/submit.php</code>
            </div>
            <div class="credential-row">
              <span class="credential-label">查询/退款</span>
              <code class="credential-value">/credit-api.php</code>
            </div>
          </div>
          <button class="btn btn-small btn-default" type="button" {{on "click" this.dismissCreated}}>我已保存，关闭</button>
        </div>
      {{/if}}

      <button class="btn btn-primary btn-small" type="button" {{on "click" this.toggleCreate}}>
        {{if this.showCreate "取消" "创建应用"}}
      </button>

      {{#if this.showCreate}}
        <div class="credit-form-card">
          <div class="form-row"><label>应用名称</label><input type="text" value={{this.newAppName}} placeholder="您的应用名称" {{on "input" this.updateNewAppName}} /></div>
          <div class="form-row"><label>应用主页 (回调地址)</label><input type="text" value={{this.newRedirectUri}} placeholder="https://your-domain.com" {{on "input" this.updateNewRedirectUri}} /></div>
          <div class="form-row"><label>通知地址 (异步回调)</label><input type="text" value={{this.newNotifyUrl}} placeholder="https://your-domain.com/api/notify" {{on "input" this.updateNewNotifyUrl}} /></div>
          <div class="form-row"><label>描述</label><textarea maxlength="200" placeholder="应用描述（选填）" {{on "input" this.updateNewDescription}}>{{this.newDescription}}</textarea></div>
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
            <div class="app-card {{if app.is_active 'active' 'inactive'}}">
              <div class="app-header" role="button" {{on "click" (fn this.toggleExpand app.id)}}>
                <div class="app-header-left">
                  <span class="app-name">{{app.app_name}}</span>
                  {{#if app.description}}<span class="app-desc">{{app.description}}</span>{{/if}}
                </div>
                <span class="app-status-badge {{if app.is_active 'active' 'inactive'}}">{{if app.is_active "启用" "停用"}}</span>
              </div>

              {{#if (eq this.expandedAppId app.id)}}
                <div class="app-detail">
                  {{#if (eq this.editingAppId app.id)}}
                    <div class="credit-form-card compact">
                      <div class="form-row"><label>应用名称</label><input type="text" value={{this.editFields.app_name}} {{on "input" (fn this.updateEditField "app_name")}} /></div>
                      <div class="form-row"><label>应用主页</label><input type="text" value={{this.editFields.redirect_uri}} placeholder="https://..." {{on "input" (fn this.updateEditField "redirect_uri")}} /></div>
                      <div class="form-row"><label>通知地址</label><input type="text" value={{this.editFields.notify_url}} placeholder="https://..." {{on "input" (fn this.updateEditField "notify_url")}} /></div>
                      <div class="form-row"><label>描述</label><input type="text" value={{this.editFields.description}} {{on "input" (fn this.updateEditField "description")}} /></div>
                      <div class="form-actions">
                        <button class="btn btn-primary btn-small" type="button" disabled={{this.editSaving}} {{on "click" this.saveEditApp}}>保存</button>
                        <button class="btn btn-default btn-small" type="button" {{on "click" this.cancelEditApp}}>取消</button>
                      </div>
                    </div>
                  {{else}}
                    <div class="app-info-grid">
                      <div class="info-row"><span class="info-label">商户ID (pid)</span><code class="info-value">{{app.client_id}}</code><button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText app.client_id)}}>复制</button></div>
                      <div class="info-row"><span class="info-label">商户密钥 (key)</span><code class="info-value secret">{{app.client_secret}}</code><button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText app.client_secret)}}>复制</button></div>
                      {{#if app.redirect_uri}}<div class="info-row"><span class="info-label">应用主页</span><span class="info-value">{{app.redirect_uri}}</span></div>{{/if}}
                      {{#if app.notify_url}}<div class="info-row"><span class="info-label">通知地址</span><span class="info-value">{{app.notify_url}}</span></div>{{/if}}
                    </div>
                    <div class="app-actions">
                      <button class="btn btn-small btn-default" type="button" {{on "click" (fn this.startEditApp app)}}>{{icon "edit"}} 编辑</button>
                      <button class="btn btn-small btn-default" type="button" {{on "click" (fn this.toggleAppStatus app)}}>{{if app.is_active "停用" "启用"}}</button>
                      <button class="btn btn-small btn-danger" type="button" {{on "click" (fn this.resetSecret app.id)}}>{{icon "key"}} 重置密钥</button>
                    </div>
                  {{/if}}

                  <div class="app-products-section">
                    <div class="products-header">
                      <h4>商品列表</h4>
                      <button class="btn btn-small btn-default" type="button" {{on "click" this.toggleProductForm}}>
                        {{if this.showProductForm "取消" "添加商品"}}
                      </button>
                    </div>

                    {{#if this.showProductForm}}
                      <div class="credit-form-card compact">
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
                            <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.toggleProductStatus p.id (eq p.status "active"))}}>
                              {{if (eq p.status "active") "下架" "上架"}}
                            </button>
                          </div>
                        {{/each}}
                      </div>
                    {{else}}
                      <p class="no-data-text">暂无商品</p>
                    {{/if}}
                  </div>
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
