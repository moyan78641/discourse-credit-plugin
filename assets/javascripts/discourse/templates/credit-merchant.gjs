import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

class CreditMerchantPage extends Component {
  @tracked products = [];
  @tracked loading = true;
  @tracked error = null;
  @tracked showCreate = false;
  @tracked creating = false;
  @tracked newName = "";
  @tracked newPrice = "";
  @tracked newDesc = "";
  @tracked newStock = "-1";
  @tracked newLimit = "0";
  @tracked newAutoDelivery = false;
  @tracked newDeliveryMsg = "";
  @tracked expandedId = null;
  @tracked cardKeys = [];
  @tracked cardKeysLoading = false;
  @tracked newCardKeys = "";
  @tracked addingKeys = false;
  @tracked editingId = null;
  @tracked editFields = {};
  @tracked editSaving = false;

  constructor() {
    super(...arguments);
    this.loadProducts();
  }

  async loadProducts() {
    try {
      const data = await ajax("/credit/merchant/products.json");
      this.products = data.products || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  @action toggleCreate() { this.showCreate = !this.showCreate; this.error = null; }
  @action updateNewName(e) { this.newName = e.target.value; }
  @action updateNewPrice(e) { this.newPrice = e.target.value; }
  @action updateNewDesc(e) { this.newDesc = e.target.value; }
  @action updateNewStock(e) { this.newStock = e.target.value; }
  @action updateNewLimit(e) { this.newLimit = e.target.value; }
  @action toggleAutoDelivery() { this.newAutoDelivery = !this.newAutoDelivery; }
  @action updateDeliveryMsg(e) { this.newDeliveryMsg = e.target.value; }

  @action async createProduct() {
    if (!this.newName || !this.newPrice) { this.error = "请填写商品名和价格"; return; }
    this.creating = true; this.error = null;
    try {
      await ajax("/credit/merchant/products.json", {
        type: "POST",
        data: {
          name: this.newName, price: this.newPrice, description: this.newDesc,
          stock: this.newStock, limit_per_user: this.newLimit,
          auto_delivery: this.newAutoDelivery, delivery_message: this.newDeliveryMsg,
        },
      });
      this.showCreate = false;
      this.newName = ""; this.newPrice = ""; this.newDesc = "";
      this.newStock = "-1"; this.newLimit = "0";
      this.newAutoDelivery = false; this.newDeliveryMsg = "";
      await this.loadProducts();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally { this.creating = false; }
  }

  @action toggleExpand(productId) {
    if (this.expandedId === productId) {
      this.expandedId = null; this.editingId = null;
    } else {
      this.expandedId = productId; this.editingId = null;
      this.loadCardKeys(productId);
    }
  }

  async loadCardKeys(productId) {
    this.cardKeysLoading = true;
    try {
      const data = await ajax(`/credit/merchant/products/${productId}/card-keys.json`);
      this.cardKeys = data.keys || [];
    } catch (_) { this.cardKeys = []; }
    finally { this.cardKeysLoading = false; }
  }

  @action updateNewCardKeys(e) { this.newCardKeys = e.target.value; }

  @action async addCardKeys(productId) {
    if (!this.newCardKeys.trim()) return;
    this.addingKeys = true;
    try {
      await ajax(`/credit/merchant/products/${productId}/card-keys.json`, {
        type: "POST", data: { keys: this.newCardKeys },
      });
      this.newCardKeys = "";
      await this.loadCardKeys(productId);
      await this.loadProducts();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "添加失败";
    } finally { this.addingKeys = false; }
  }

  @action startEdit(p) {
    this.editingId = p.id;
    this.editFields = { name: p.name, price: p.price, description: p.description || "", stock: p.stock, limit_per_user: p.limit_per_user || 0, auto_delivery: p.auto_delivery, delivery_message: p.delivery_message || "" };
  }
  @action cancelEdit() { this.editingId = null; }
  @action updateEditField(field, e) { this.editFields = { ...this.editFields, [field]: e.target.value }; }
  @action toggleEditAutoDelivery() { this.editFields = { ...this.editFields, auto_delivery: !this.editFields.auto_delivery }; }

  @action async saveEdit() {
    this.editSaving = true;
    try {
      await ajax(`/credit/merchant/products/${this.editingId}.json`, { type: "PUT", data: this.editFields });
      this.editingId = null;
      await this.loadProducts();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "保存失败";
    } finally { this.editSaving = false; }
  }

  @action async toggleStatus(p) {
    try {
      await ajax(`/credit/merchant/products/${p.id}.json`, { type: "PUT", data: { status: p.status === "active" ? "inactive" : "active" } });
      await this.loadProducts();
    } catch (_) { /* ignore */ }
  }

  @action copyLink(productId) {
    const url = `${window.location.origin}/credit/product/${productId}`;
    navigator.clipboard.writeText(url);
  }

  <template>
    <div class="credit-merchant-page">
      <h2>{{icon "store"}} 商户中心</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      <button class="btn btn-primary btn-small" type="button" {{on "click" this.toggleCreate}}>
        {{if this.showCreate "取消" "添加商品"}}
      </button>

      {{#if this.showCreate}}
        <div class="credit-form-card">
          <div class="form-row"><label>商品名称</label><input type="text" value={{this.newName}} placeholder="商品名称" {{on "input" this.updateNewName}} /></div>
          <div class="form-row"><label>价格（积分）</label><input type="number" min="0.01" step="0.01" value={{this.newPrice}} {{on "input" this.updateNewPrice}} /></div>
          <div class="form-row"><label>描述</label><textarea maxlength="500" placeholder="商品描述（选填）" {{on "input" this.updateNewDesc}}>{{this.newDesc}}</textarea></div>
          <div class="form-row"><label>库存（-1无限）</label><input type="number" value={{this.newStock}} {{on "input" this.updateNewStock}} /></div>
          <div class="form-row"><label>限购（0不限）</label><input type="number" min="0" value={{this.newLimit}} {{on "input" this.updateNewLimit}} /></div>
          <div class="form-row">
            <label><input type="checkbox" checked={{this.newAutoDelivery}} {{on "click" this.toggleAutoDelivery}} /> 自动发货（发卡密）</label>
          </div>
          {{#if this.newAutoDelivery}}
            <div class="form-row"><label>发货附言</label><input type="text" value={{this.newDeliveryMsg}} placeholder="站内信附言（选填）" {{on "input" this.updateDeliveryMsg}} /></div>
          {{/if}}
          <button class="btn btn-primary" type="button" disabled={{this.creating}} {{on "click" this.createProduct}}>
            {{if this.creating "创建中..." "确认创建"}}
          </button>
        </div>
      {{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.products.length}}
        <div class="credit-products-list">
          {{#each this.products as |p|}}
            <div class="product-card {{if (eq p.status 'active') 'active' 'inactive'}}">
              <div class="product-card-header" role="button" {{on "click" (fn this.toggleExpand p.id)}}>
                <div class="product-card-left">
                  <span class="product-card-name">{{p.name}}</span>
                  <span class="product-card-price">{{p.price}} 积分</span>
                </div>
                <div class="product-card-right">
                  {{#if p.auto_delivery}}<span class="auto-delivery-badge">自动发货</span>{{/if}}
                  <span class="product-status-badge {{if (eq p.status 'active') 'active' 'inactive'}}">{{if (eq p.status "active") "上架" "下架"}}</span>
                </div>
              </div>

              {{#if (eq this.expandedId p.id)}}
                <div class="product-card-detail">
                  {{#if (eq this.editingId p.id)}}
                    <div class="credit-form-card compact">
                      <div class="form-row"><label>名称</label><input type="text" value={{this.editFields.name}} {{on "input" (fn this.updateEditField "name")}} /></div>
                      <div class="form-row"><label>价格</label><input type="number" min="0.01" step="0.01" value={{this.editFields.price}} {{on "input" (fn this.updateEditField "price")}} /></div>
                      <div class="form-row"><label>描述</label><input type="text" value={{this.editFields.description}} {{on "input" (fn this.updateEditField "description")}} /></div>
                      <div class="form-row"><label>库存</label><input type="number" value={{this.editFields.stock}} {{on "input" (fn this.updateEditField "stock")}} /></div>
                      <div class="form-row">
                        <label><input type="checkbox" checked={{this.editFields.auto_delivery}} {{on "click" this.toggleEditAutoDelivery}} /> 自动发货</label>
                      </div>
                      {{#if this.editFields.auto_delivery}}
                        <div class="form-row"><label>发货附言</label><input type="text" value={{this.editFields.delivery_message}} {{on "input" (fn this.updateEditField "delivery_message")}} /></div>
                      {{/if}}
                      <div class="form-actions">
                        <button class="btn btn-primary btn-small" type="button" disabled={{this.editSaving}} {{on "click" this.saveEdit}}>保存</button>
                        <button class="btn btn-default btn-small" type="button" {{on "click" this.cancelEdit}}>取消</button>
                      </div>
                    </div>
                  {{else}}
                    <div class="product-info-grid">
                      {{#if p.description}}<div class="info-row"><span class="info-label">描述</span><span class="info-value">{{p.description}}</span></div>{{/if}}
                      <div class="info-row"><span class="info-label">库存</span><span class="info-value">{{if (eq p.stock -1) "无限" p.stock}}</span></div>
                      <div class="info-row"><span class="info-label">已售</span><span class="info-value">{{p.sold_count}}</span></div>
                      {{#if p.auto_delivery}}<div class="info-row"><span class="info-label">可用卡密</span><span class="info-value">{{p.card_key_count}}</span></div>{{/if}}
                      <div class="info-row"><span class="info-label">购买链接</span><span class="info-value"><a href="/credit/product/{{p.id}}">/credit/product/{{p.id}}</a> <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyLink p.id)}}>复制</button></span></div>
                    </div>
                    <div class="product-actions">
                      <button class="btn btn-small btn-default" type="button" {{on "click" (fn this.startEdit p)}}>{{icon "pen-to-square"}} 编辑</button>
                      <button class="btn btn-small {{if (eq p.status 'active') 'btn-default' 'btn-primary'}}" type="button" {{on "click" (fn this.toggleStatus p)}}>{{if (eq p.status "active") "下架" "上架"}}</button>
                    </div>
                  {{/if}}

                  {{!-- 卡密管理 --}}
                  {{#if p.auto_delivery}}
                    <div class="card-keys-section">
                      <h4>卡密管理</h4>
                      <div class="form-row">
                        <textarea placeholder="每行一个卡密" rows="4" {{on "input" this.updateNewCardKeys}}>{{this.newCardKeys}}</textarea>
                      </div>
                      <button class="btn btn-small btn-primary" type="button" disabled={{this.addingKeys}} {{on "click" (fn this.addCardKeys p.id)}}>
                        {{if this.addingKeys "添加中..." "添加卡密"}}
                      </button>

                      {{#if this.cardKeysLoading}}
                        <p class="loading-text">加载卡密...</p>
                      {{else if this.cardKeys.length}}
                        <div class="card-keys-list">
                          {{#each this.cardKeys as |k|}}
                            <div class="card-key-row {{k.status}}">
                              <span class="card-key-value">{{k.card_key}}</span>
                              <span class="card-key-status">{{if (eq k.status "available") "可用" "已售"}}</span>
                            </div>
                          {{/each}}
                        </div>
                      {{else}}
                        <p class="no-data-text">暂无卡密</p>
                      {{/if}}
                    </div>
                  {{/if}}
                </div>
              {{/if}}
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="no-data-text">暂无商品，点击上方按钮添加</p>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditMerchantPage /></template>);
