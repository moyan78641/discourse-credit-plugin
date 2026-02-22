import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

class CreditRedEnvelopePage extends Component {
  @tracked tab = "create";
  @tracked envelopeType = "fixed";
  @tracked amount = "";
  @tracked count = "";
  @tracked message = "";
  @tracked payKey = "";
  @tracked error = null;
  @tracked success = null;
  @tracked submitting = false;
  @tracked sentList = [];
  @tracked receivedList = [];
  @tracked listLoading = false;

  @action switchTab(t) {
    this.tab = t;
    this.error = null;
    this.success = null;
    if (t === "sent") this.loadSent();
    if (t === "received") this.loadReceived();
  }

  @action updateType(e) { this.envelopeType = e.target.value; }
  @action updateAmount(e) { this.amount = e.target.value; }
  @action updateCount(e) { this.count = e.target.value; }
  @action updateMessage(e) { this.message = e.target.value; }
  @action updatePayKey(e) { this.payKey = e.target.value; }

  @action async createEnvelope() {
    this.error = null;
    this.success = null;
    if (!this.amount || !this.count || !this.payKey) {
      this.error = "请填写完整信息";
      return;
    }
    this.submitting = true;
    try {
      const data = await ajax("/credit/redenvelope/create.json", {
        type: "POST",
        data: {
          type: this.envelopeType,
          amount: this.amount,
          count: this.count,
          message: this.message,
          pay_key: this.payKey,
        },
      });
      this.success = `红包创建成功！ID: ${data.id}`;
      this.amount = "";
      this.count = "";
      this.payKey = "";
      this.message = "";
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "创建失败";
    } finally {
      this.submitting = false;
    }
  }

  async loadSent() {
    this.listLoading = true;
    try {
      const data = await ajax("/credit/redenvelope/list.json?type=sent");
      this.sentList = data.list || [];
    } catch (_) { /* ignore */ }
    finally { this.listLoading = false; }
  }

  async loadReceived() {
    this.listLoading = true;
    try {
      const data = await ajax("/credit/redenvelope/list.json?type=received");
      this.receivedList = data.list || [];
    } catch (_) { /* ignore */ }
    finally { this.listLoading = false; }
  }

  <template>
    <div class="credit-redenvelope-page">
      <h2>🧧 红包</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">← 返回钱包</a>

      <div class="credit-tabs">
        <button class="btn {{if this.isCreate 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "create")}}>发红包</button>
        <button class="btn {{if this.isSent 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "sent")}}>已发出</button>
        <button class="btn {{if this.isReceived 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "received")}}>已领取</button>
      </div>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}
      {{#if this.success}}<div class="credit-success">{{this.success}}</div>{{/if}}

      {{#if this.isCreate}}
          <div class="credit-form-card">
            <div class="form-row">
              <label>类型</label>
              <select {{on "change" this.updateType}}>
                <option value="fixed">等额红包</option>
                <option value="random">随机红包</option>
              </select>
            </div>
            <div class="form-row">
              <label>总金额</label>
              <input type="number" min="0.01" step="0.01" value={{this.amount}} placeholder="红包总金额" {{on "input" this.updateAmount}} />
            </div>
            <div class="form-row">
              <label>个数</label>
              <input type="number" min="1" value={{this.count}} placeholder="红包个数" {{on "input" this.updateCount}} />
            </div>
            <div class="form-row">
              <label>祝福语（选填）</label>
              <input type="text" maxlength="50" value={{this.message}} placeholder="恭喜发财" {{on "input" this.updateMessage}} />
            </div>
            <div class="form-row">
              <label>支付密码</label>
              <input type="password" maxlength="6" value={{this.payKey}} placeholder="6位数字密码" {{on "input" this.updatePayKey}} />
            </div>
            <button class="btn btn-primary" type="button" disabled={{this.submitting}} {{on "click" this.createEnvelope}}>
              {{if this.submitting "创建中..." "🧧 发红包"}}
            </button>
          </div>
      {{/if}}

      {{#if this.listLoading}}
        <p class="loading-text">加载中...</p>
      {{/if}}

      {{#if this.sentList.length}}
        <div class="credit-list">
          {{#each this.sentList as |e|}}
            <a href="/credit/redenvelope/{{e.id}}" class="credit-list-row">
              <div class="list-info">
                <span class="list-title">🧧 {{e.type}} · {{e.total_count}}个</span>
                <span class="list-meta">{{e.message}} · {{e.status}}</span>
              </div>
              <span class="list-amount">{{e.total_amount}}</span>
            </a>
          {{/each}}
        </div>
      {{/if}}

      {{#if this.receivedList.length}}
        <div class="credit-list">
          {{#each this.receivedList as |c|}}
            <a href="/credit/redenvelope/{{c.id}}" class="credit-list-row">
              <div class="list-info">
                <span class="list-title">来自 {{c.sender_username}}</span>
                <span class="list-meta">{{c.message}}</span>
              </div>
              <span class="list-amount income">+{{c.amount}}</span>
            </a>
          {{/each}}
        </div>
      {{/if}}
    </div>
  </template>
}

// Tab state getters for template
Object.defineProperty(CreditRedEnvelopePage.prototype, "isCreate", {
  get() { return this.tab === "create"; },
});
Object.defineProperty(CreditRedEnvelopePage.prototype, "isSent", {
  get() { return this.tab === "sent"; },
});
Object.defineProperty(CreditRedEnvelopePage.prototype, "isReceived", {
  get() { return this.tab === "received"; },
});

export default RouteTemplate(<template><CreditRedEnvelopePage /></template>);
