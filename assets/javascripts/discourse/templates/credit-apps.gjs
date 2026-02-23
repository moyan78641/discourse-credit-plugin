import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { ajax } from "discourse/lib/ajax";
import icon from "discourse/helpers/d-icon";

class CreditAppsPage extends Component {
  @tracked apps = [];
  @tracked loading = true;
  @tracked error = null;
  @tracked showCreate = false;
  @tracked creating = false;
  @tracked newName = "";
  @tracked newCallback = "";
  @tracked newDesc = "";
  @tracked expandedId = null;
  @tracked editingId = null;
  @tracked editFields = {};
  @tracked editSaving = false;
  @tracked copiedField = null;
  @tracked testingAppId = null;
  @tracked testAmount = "10";
  @tracked testDesc = "测试支付";
  @tracked testLoading = false;
  @tracked testResult = null;
  @tracked testError = null;

  constructor() {
    super(...arguments);
    this.loadApps();
  }

  async loadApps() {
    try {
      const data = await ajax("/credit/apps.json");
      this.apps = data.apps || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  @action toggleCreate() { this.showCreate = !this.showCreate; this.error = null; }
  @action updateNewName(e) { this.newName = e.target.value; }
  @action updateNewCallback(e) { this.newCallback = e.target.value; }
  @action updateNewDesc(e) { this.newDesc = e.target.value; }

  @action async createApp() {
    if (!this.newName.trim()) { this.error = "请填写应用名称"; return; }
    this.creating = true; this.error = null;
    try {
      await ajax("/credit/apps.json", {
        type: "POST",
        data: { app_name: this.newName, callback_url: this.newCallback, description: this.newDesc },
      });
      this.showCreate = false;
      this.newName = ""; this.newCallback = ""; this.newDesc = "";
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally { this.creating = false; }
  }

  @action toggleExpand(appId) {
    this.expandedId = this.expandedId === appId ? null : appId;
    this.editingId = null;
  }

  @action startEdit(app) {
    this.editingId = app.id;
    this.editFields = {
      app_name: app.app_name,
      callback_url: app.callback_url || "",
      description: app.description || "",
    };
  }
  @action cancelEdit() { this.editingId = null; }
  @action updateEditField(field, e) {
    this.editFields = { ...this.editFields, [field]: e.target.value };
  }

  @action async saveEdit() {
    this.editSaving = true;
    try {
      await ajax(`/credit/apps/${this.editingId}.json`, { type: "PUT", data: this.editFields });
      this.editingId = null;
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "保存失败";
    } finally { this.editSaving = false; }
  }

  @action async toggleActive(app) {
    try {
      await ajax(`/credit/apps/${app.id}.json`, {
        type: "PUT", data: { is_active: !app.is_active },
      });
      await this.loadApps();
    } catch (_) { /* ignore */ }
  }

  @action async regenerateToken(appId) {
    if (!confirm("重新生成 Token 后，旧 Token 将立即失效。确定继续？")) return;
    try {
      await ajax(`/credit/apps/${appId}/token.json`, { type: "POST" });
      await this.loadApps();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "操作失败";
    }
  }

  @action copyText(text, field) {
    navigator.clipboard.writeText(text);
    this.copiedField = field;
    setTimeout(() => { this.copiedField = null; }, 1500);
  }

  @action openTestPayment(appId) {
    this.testingAppId = appId;
    this.testAmount = "10";
    this.testDesc = "测试支付";
    this.testResult = null;
    this.testError = null;
  }
  @action closeTestPayment() { this.testingAppId = null; this.testResult = null; this.testError = null; }
  @action stopPropagation(e) { e.stopPropagation(); }
  @action updateTestAmount(e) { this.testAmount = e.target.value; }
  @action updateTestDesc(e) { this.testDesc = e.target.value; }

  @action async submitTestPayment() {
    this.testLoading = true;
    this.testResult = null;
    this.testError = null;
    try {
      const data = await ajax(`/credit/apps/${this.testingAppId}/test-payment.json`, {
        type: "POST",
        data: { amount: this.testAmount, description: this.testDesc },
      });
      this.testResult = data;
    } catch (e) {
      this.testError = e.jqXHR?.responseJSON?.error || "测试支付发起失败";
    } finally { this.testLoading = false; }
  }

  <template>
    <div class="credit-apps-page">
      <h2>{{icon "bolt-lightning"}} 我的应用</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      <p class="apps-intro">
        创建应用后，可通过 API 接入积分支付。
        <a href="https://sparkloc.com/t/topic/49" target="_blank" rel="noopener">查看对接指南 →</a>
      </p>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      <button class="btn btn-primary btn-small" type="button" {{on "click" this.toggleCreate}}>
        {{if this.showCreate "取消" "创建应用"}}
      </button>

      {{#if this.showCreate}}
        <div class="credit-form-card">
          <div class="form-row"><label>应用名称</label><input type="text" value={{this.newName}} placeholder="例如：我的网站" {{on "input" this.updateNewName}} /></div>
          <div class="form-row"><label>回调地址</label><input type="text" value={{this.newCallback}} placeholder="https://example.com/callback" {{on "input" this.updateNewCallback}} /></div>
          <div class="form-row"><label>描述</label><input type="text" value={{this.newDesc}} placeholder="应用描述（选填）" {{on "input" this.updateNewDesc}} /></div>
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
            <div class="app-card {{unless app.is_active 'inactive'}}">
              <div class="app-card-header" role="button" {{on "click" (fn this.toggleExpand app.id)}}>
                <div class="app-card-left">
                  <span class="app-card-name">{{app.app_name}}</span>
                  <span class="app-status-badge {{if app.is_active 'active' 'inactive'}}">
                    {{if app.is_active "启用" "停用"}}
                  </span>
                </div>
                <span class="app-card-date">{{app.created_at}}</span>
              </div>

              {{#if (eq this.expandedId app.id)}}
                <div class="app-card-detail">
                  {{#if (eq this.editingId app.id)}}
                    <div class="credit-form-card compact">
                      <div class="form-row"><label>名称</label><input type="text" value={{this.editFields.app_name}} {{on "input" (fn this.updateEditField "app_name")}} /></div>
                      <div class="form-row"><label>回调地址</label><input type="text" value={{this.editFields.callback_url}} {{on "input" (fn this.updateEditField "callback_url")}} /></div>
                      <div class="form-row"><label>描述</label><input type="text" value={{this.editFields.description}} {{on "input" (fn this.updateEditField "description")}} /></div>
                      <div class="form-actions">
                        <button class="btn btn-primary btn-small" type="button" disabled={{this.editSaving}} {{on "click" this.saveEdit}}>保存</button>
                        <button class="btn btn-default btn-small" type="button" {{on "click" this.cancelEdit}}>取消</button>
                      </div>
                    </div>
                  {{else}}
                    <div class="app-credentials">
                      <div class="credential-row">
                        <span class="credential-label">Payment ID (client_id)</span>
                        <code class="credential-value">{{app.client_id}}</code>
                        <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText app.client_id "client_id")}}>
                          {{if (eq this.copiedField "client_id") "已复制" "复制"}}
                        </button>
                      </div>
                      <div class="credential-row">
                        <span class="credential-label">Token</span>
                        <code class="credential-value token">{{app.token}}</code>
                        <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.copyText app.token "token")}}>
                          {{if (eq this.copiedField "token") "已复制" "复制"}}
                        </button>
                      </div>
                      <div class="credential-row">
                        <span class="credential-label">回调地址</span>
                        <span class="credential-value">{{if app.callback_url app.callback_url "未设置"}}</span>
                      </div>
                      {{#if app.description}}
                        <div class="credential-row">
                          <span class="credential-label">描述</span>
                          <span class="credential-value">{{app.description}}</span>
                        </div>
                      {{/if}}
                    </div>
                    <div class="app-actions">
                      <button class="btn btn-small btn-default" type="button" {{on "click" (fn this.startEdit app)}}>{{icon "pen-to-square"}} 编辑</button>
                      <button class="btn btn-small {{if app.is_active 'btn-default' 'btn-primary'}}" type="button" {{on "click" (fn this.toggleActive app)}}>
                        {{if app.is_active "停用" "启用"}}
                      </button>
                      <button class="btn btn-small btn-danger" type="button" {{on "click" (fn this.regenerateToken app.id)}}>{{icon "key"}} 重置 Token</button>
                      {{#if app.is_active}}
                        <button class="btn btn-small btn-primary" type="button" {{on "click" (fn this.openTestPayment app.id)}}>{{icon "bolt-lightning"}} 测试支付</button>
                      {{/if}}
                    </div>
                  {{/if}}
                </div>
              {{/if}}
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="no-data-text">暂无应用，点击上方按钮创建</p>
      {{/if}}

      {{#if this.testingAppId}}
        <div class="credit-modal-overlay" role="button" {{on "click" this.closeTestPayment}}>
          <div class="credit-modal-card" role="presentation" {{on "click" this.stopPropagation}}>
            <h3>{{icon "bolt-lightning"}} 测试支付</h3>
            <p class="test-hint">测试模式不会产生实际的余额变动，仅生成订单记录和回调。</p>
            {{#if this.testError}}<div class="credit-error">{{this.testError}}</div>{{/if}}
            {{#if this.testResult}}
              <div class="test-result-card">
                <p class="test-success-text">{{icon "check"}} 测试交易已创建</p>
                <div class="credential-row">
                  <span class="credential-label">交易ID</span>
                  <code class="credential-value">{{this.testResult.transaction_id}}</code>
                </div>
                <a href={{this.testResult.payment_url}} class="btn btn-primary" target="_blank" rel="noopener">打开支付页面</a>
                <button class="btn btn-default" type="button" {{on "click" this.closeTestPayment}}>关闭</button>
              </div>
            {{else}}
              <div class="credit-form-card compact">
                <div class="form-row">
                  <label>支付金额</label>
                  <input type="number" min="1" value={{this.testAmount}} {{on "input" this.updateTestAmount}} />
                </div>
                <div class="form-row">
                  <label>交易描述</label>
                  <input type="text" value={{this.testDesc}} {{on "input" this.updateTestDesc}} />
                </div>
                <div class="form-actions">
                  <button class="btn btn-primary" type="button" disabled={{this.testLoading}} {{on "click" this.submitTestPayment}}>
                    {{if this.testLoading "创建中..." "发起测试"}}
                  </button>
                  <button class="btn btn-default" type="button" {{on "click" this.closeTestPayment}}>取消</button>
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditAppsPage /></template>);
