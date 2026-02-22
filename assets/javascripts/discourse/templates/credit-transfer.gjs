import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

class CreditTransferPage extends Component {
  @tracked toUsername = "";
  @tracked amount = "";
  @tracked remark = "";
  @tracked payKey = "";
  @tracked error = null;
  @tracked success = null;
  @tracked submitting = false;
  @tracked searchResults = [];
  @tracked searching = false;
  @tracked searchTimer = null;

  @action updateTo(e) {
    this.toUsername = e.target.value;
    this.success = null;
    this.error = null;
    clearTimeout(this.searchTimer);
    if (this.toUsername.length >= 2) {
      this.searchTimer = setTimeout(() => this.searchUser(), 300);
    } else {
      this.searchResults = [];
    }
  }

  @action selectUser(username) {
    this.toUsername = username;
    this.searchResults = [];
  }

  @action updateAmount(e) { this.amount = e.target.value; }
  @action updateRemark(e) { this.remark = e.target.value; }
  @action updatePayKey(e) { this.payKey = e.target.value; }

  async searchUser() {
    this.searching = true;
    try {
      const data = await ajax(`/credit/search-user.json?keyword=${encodeURIComponent(this.toUsername)}`);
      this.searchResults = data.users || [];
    } catch (_) { this.searchResults = []; }
    finally { this.searching = false; }
  }

  @action async doTransfer() {
    this.error = null;
    this.success = null;
    if (!this.toUsername || !this.amount || !this.payKey) {
      this.error = "请填写完整信息";
      return;
    }
    this.submitting = true;
    try {
      await ajax("/credit/transfer.json", {
        type: "POST",
        data: { to_username: this.toUsername, amount: this.amount, remark: this.remark, pay_key: this.payKey },
      });
      this.success = `成功转账 ${this.amount} 积分给 ${this.toUsername}`;
      this.amount = "";
      this.payKey = "";
      this.remark = "";
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "转账失败";
    } finally {
      this.submitting = false;
    }
  }

  <template>
    <div class="credit-transfer-page">
      <h2>{{icon "right-left"}} 转账</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}
      {{#if this.success}}<div class="credit-success">{{this.success}}</div>{{/if}}

      <div class="credit-form-card">
        <div class="form-row">
          <label>收款人</label>
          <input type="text" value={{this.toUsername}} placeholder="输入用户名搜索" {{on "input" this.updateTo}} />
          {{#if this.searchResults.length}}
            <div class="credit-search-dropdown">
              {{#each this.searchResults as |u|}}
                <div class="search-item" role="button" {{on "click" (fn this.selectUser u.username)}}>
                  {{u.username}} {{#if u.name}}<span class="search-name">({{u.name}})</span>{{/if}}
                </div>
              {{/each}}
            </div>
          {{/if}}
        </div>
        <div class="form-row">
          <label>金额</label>
          <input type="number" min="0.01" step="0.01" value={{this.amount}} placeholder="转账金额" {{on "input" this.updateAmount}} />
        </div>
        <div class="form-row">
          <label>备注（选填）</label>
          <input type="text" maxlength="100" value={{this.remark}} placeholder="转账备注" {{on "input" this.updateRemark}} />
        </div>
        <div class="form-row">
          <label>支付密码</label>
          <input type="password" maxlength="6" value={{this.payKey}} placeholder="6位数字密码" {{on "input" this.updatePayKey}} />
        </div>
        <button class="btn btn-primary" type="button" disabled={{this.submitting}} {{on "click" this.doTransfer}}>
          {{if this.submitting "转账中..." "确认转账"}}
        </button>
      </div>
    </div>
  </template>
}

export default RouteTemplate(<template><CreditTransferPage /></template>);
