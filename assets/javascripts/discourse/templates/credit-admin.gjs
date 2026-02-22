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

class CreditAdminPage extends Component {
  @tracked tab = "stats";
  @tracked stats = null;
  @tracked configs = [];
  @tracked users = [];
  @tracked usersTotal = 0;
  @tracked usersPage = 1;
  @tracked userSearch = "";
  @tracked loading = true;
  @tracked error = null;
  @tracked editKey = null;
  @tracked editValue = "";
  @tracked balanceUserId = null;
  @tracked balanceAmount = "";
  @tracked balanceRemark = "";
  @tracked payConfigs = [];
  @tracked payConfigsLoading = false;
  @tracked editPayLevel = null;
  @tracked editPayFields = {};

  constructor() {
    super(...arguments);
    this.loadStats();
  }

  get isStatsTab() { return this.tab === "stats"; }
  get isConfigsTab() { return this.tab === "configs"; }
  get isUsersTab() { return this.tab === "users"; }
  get isFeesTab() { return this.tab === "fees"; }

  @action switchTab(t) {
    this.tab = t;
    this.error = null;
    if (t === "stats") this.loadStats();
    if (t === "configs") this.loadConfigs();
    if (t === "users") this.loadUsers();
    if (t === "fees") this.loadPayConfigs();
  }

  async loadStats() {
    this.loading = true;
    try {
      const data = await ajax("/credit/admin/stats.json");
      this.stats = data;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally {
      this.loading = false;
    }
  }

  async loadConfigs() {
    this.loading = true;
    try {
      const data = await ajax("/credit/admin/configs.json");
      this.configs = data.configs || [];
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  async loadUsers() {
    this.loading = true;
    try {
      let url = `/credit/admin/users.json?page=${this.usersPage}`;
      if (this.userSearch) url += `&search=${encodeURIComponent(this.userSearch)}`;
      const data = await ajax(url);
      this.users = data.list || [];
      this.usersTotal = data.total || 0;
    } catch (_) { /* ignore */ }
    finally { this.loading = false; }
  }

  async loadPayConfigs() {
    this.payConfigsLoading = true;
    try {
      const data = await ajax("/credit/admin/pay-configs.json");
      this.payConfigs = data.configs || [];
    } catch (_) { /* ignore */ }
    finally { this.payConfigsLoading = false; }
  }

  @action startEditConfig(key, value) { this.editKey = key; this.editValue = value; }
  @action updateEditValue(e) { this.editValue = e.target.value; }

  @action async saveConfig() {
    try {
      await ajax("/credit/admin/configs.json", {
        type: "PUT",
        data: { key: this.editKey, value: this.editValue },
      });
      this.editKey = null;
      await this.loadConfigs();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "保存失败";
    }
  }

  @action async initConfigs() {
    try {
      await ajax("/credit/admin/configs/init.json", { type: "POST" });
      await this.loadConfigs();
    } catch (_) { /* ignore */ }
  }

  @action updateUserSearch(e) { this.userSearch = e.target.value; }
  @action searchUsers() { this.usersPage = 1; this.loadUsers(); }

  @action async toggleAdmin(userId, currentAdmin) {
    try {
      await ajax("/credit/admin/users/admin.json", {
        type: "PUT",
        data: { user_id: userId, is_admin: !currentAdmin },
      });
      await this.loadUsers();
    } catch (_) { /* ignore */ }
  }

  @action startBalance(userId) { this.balanceUserId = userId; this.balanceAmount = ""; this.balanceRemark = ""; }
  @action updateBalanceAmount(e) { this.balanceAmount = e.target.value; }
  @action updateBalanceRemark(e) { this.balanceRemark = e.target.value; }

  @action async saveBalance() {
    if (!this.balanceAmount) return;
    try {
      await ajax("/credit/admin/users/balance.json", {
        type: "PUT",
        data: { user_id: this.balanceUserId, amount: this.balanceAmount, remark: this.balanceRemark },
      });
      this.balanceUserId = null;
      await this.loadUsers();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "调整失败";
    }
  }

  @action startEditPayConfig(cfg) {
    this.editPayLevel = cfg.level;
    this.editPayFields = {
      min_score: cfg.min_score,
      max_score: cfg.max_score || "",
      daily_limit: cfg.daily_limit || "",
      fee_rate: cfg.fee_rate,
      score_rate: cfg.score_rate || 0,
    };
  }

  @action updatePayField(field, e) {
    this.editPayFields = { ...this.editPayFields, [field]: e.target.value };
  }

  @action async savePayConfig() {
    try {
      await ajax("/credit/admin/pay-configs.json", {
        type: "PUT",
        data: { level: this.editPayLevel, ...this.editPayFields },
      });
      this.editPayLevel = null;
      await this.loadPayConfigs();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "保存失败";
    }
  }

  @action cancelEditPayConfig() { this.editPayLevel = null; }

  <template>
    <div class="credit-admin-page">
      <h2>{{icon "gears"}} 积分管理后台</h2>
      <a href="/credit" class="btn btn-small btn-default credit-back-btn">{{icon "arrow-left"}} 返回钱包</a>

      <div class="credit-tabs">
        <button class="btn {{if this.isStatsTab 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "stats")}}>{{icon "chart-line"}} 统计</button>
        <button class="btn {{if this.isFeesTab 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "fees")}}>{{icon "wallet"}} 费率等级</button>
        <button class="btn {{if this.isConfigsTab 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "configs")}}>{{icon "gears"}} 系统配置</button>
        <button class="btn {{if this.isUsersTab 'btn-primary' 'btn-default'}}" type="button" {{on "click" (fn this.switchTab "users")}}>{{icon "magnifying-glass"}} 用户</button>
      </div>

      {{#if this.error}}<div class="credit-error">{{this.error}}</div>{{/if}}

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else}}

        {{#if this.isStatsTab}}
          {{#if this.stats}}
            <div class="admin-stats-grid">
              <div class="admin-stat-card">
                <div class="stat-icon">{{icon "wallet"}}</div>
                <span class="stat-label">钱包用户数</span>
                <span class="stat-value">{{this.stats.user_count}}</span>
              </div>
              <div class="admin-stat-card">
                <div class="stat-icon">{{icon "chart-line"}}</div>
                <span class="stat-label">总余额</span>
                <span class="stat-value">{{this.stats.total_balance}}</span>
              </div>
              <div class="admin-stat-card">
                <div class="stat-icon">{{icon "right-left"}}</div>
                <span class="stat-label">今日订单</span>
                <span class="stat-value">{{this.stats.today_orders}}</span>
              </div>
            </div>
          {{/if}}
        {{/if}}

        {{#if this.isFeesTab}}
          {{#if this.payConfigsLoading}}
            <p class="loading-text">加载中...</p>
          {{else}}
            <div class="admin-section-header">
              <h3>会员等级与费率</h3>
              <p class="section-desc">不同等级的用户享受不同的手续费率和每日限额</p>
            </div>
            <div class="admin-pay-configs">
              <div class="pay-config-header">
                <span>等级</span><span>最低分</span><span>最高分</span><span>费率</span><span>每日限额</span><span>操作</span>
              </div>
              {{#each this.payConfigs as |cfg|}}
                {{#if (eq this.editPayLevel cfg.level)}}
                  <div class="pay-config-row editing">
                    <span class="pay-level-badge level-{{cfg.level}}">Lv.{{cfg.level}}</span>
                    <input type="number" value={{this.editPayFields.min_score}} {{on "input" (fn this.updatePayField "min_score")}} />
                    <input type="number" value={{this.editPayFields.max_score}} placeholder="无上限" {{on "input" (fn this.updatePayField "max_score")}} />
                    <input type="number" step="0.0001" value={{this.editPayFields.fee_rate}} {{on "input" (fn this.updatePayField "fee_rate")}} />
                    <input type="number" value={{this.editPayFields.daily_limit}} placeholder="不限" {{on "input" (fn this.updatePayField "daily_limit")}} />
                    <div class="row-actions">
                      <button class="btn btn-small btn-primary" type="button" {{on "click" this.savePayConfig}}>保存</button>
                      <button class="btn btn-small btn-default" type="button" {{on "click" this.cancelEditPayConfig}}>取消</button>
                    </div>
                  </div>
                {{else}}
                  <div class="pay-config-row">
                    <span class="pay-level-badge level-{{cfg.level}}">Lv.{{cfg.level}}</span>
                    <span>{{cfg.min_score}}</span>
                    <span>{{if cfg.max_score cfg.max_score "无上限"}}</span>
                    <span>{{cfg.fee_rate}}</span>
                    <span>{{if cfg.daily_limit cfg.daily_limit "不限"}}</span>
                    <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.startEditPayConfig cfg)}}>{{icon "pen-to-square"}} 编辑</button>
                  </div>
                {{/if}}
              {{/each}}
            </div>

            <div class="admin-section-header" style="margin-top: 24px;">
              <h3>关键费率说明</h3>
            </div>
            <div class="admin-fee-info">
              <div class="fee-info-row">
                <span class="fee-label">转账手续费率</span>
                <span class="fee-key">transfer_fee_rate</span>
                <span class="fee-desc">用户转账时从发送金额中扣除的手续费比例</span>
              </div>
              <div class="fee-info-row">
                <span class="fee-label">商户手续费率</span>
                <span class="fee-key">merchant_fee_rate</span>
                <span class="fee-desc">商户收款时从订单金额中扣除的手续费比例</span>
              </div>
              <div class="fee-info-row">
                <span class="fee-label">红包手续费率</span>
                <span class="fee-key">red_envelope_fee_rate</span>
                <span class="fee-desc">发红包时额外收取的手续费比例</span>
              </div>
              <p class="fee-tip">以上费率可在「系统配置」标签页中修改具体数值</p>
            </div>
          {{/if}}
        {{/if}}

        {{#if this.isConfigsTab}}
          <button class="btn btn-small btn-default" type="button" {{on "click" this.initConfigs}}>{{icon "plus"}} 初始化默认配置</button>
          <div class="admin-configs-list">
            {{#each this.configs as |cfg|}}
              <div class="config-row">
                <span class="config-key">{{cfg.key}}</span>
                <span class="config-desc">{{cfg.description}}</span>
                {{#if (eq this.editKey cfg.key)}}
                  <input type="text" value={{this.editValue}} {{on "input" this.updateEditValue}} />
                  <button class="btn btn-small btn-primary" type="button" {{on "click" this.saveConfig}}>保存</button>
                {{else}}
                  <span class="config-value">{{cfg.value}}</span>
                  <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.startEditConfig cfg.key cfg.value)}}>{{icon "pen-to-square"}} 编辑</button>
                {{/if}}
              </div>
            {{/each}}
          </div>
        {{/if}}

        {{#if this.isUsersTab}}
          <div class="admin-user-search">
            <input type="text" placeholder="搜索用户名" value={{this.userSearch}} {{on "input" this.updateUserSearch}} />
            <button class="btn btn-small btn-default" type="button" {{on "click" this.searchUsers}}>{{icon "magnifying-glass"}} 搜索</button>
          </div>
          <div class="admin-users-list">
            {{#each this.users as |u|}}
              <div class="admin-user-row">
                <div class="user-info">
                  <span class="user-name">{{u.username}}</span>
                  {{#if u.is_admin}}<span class="admin-badge">管理员</span>{{/if}}
                </div>
                <div class="user-balance">余额: {{u.available_balance}}</div>
                <div class="user-actions">
                  <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.toggleAdmin u.user_id u.is_admin)}}>
                    {{if u.is_admin "取消管理员" "设为管理员"}}
                  </button>
                  <button class="btn btn-flat btn-small" type="button" {{on "click" (fn this.startBalance u.user_id)}}>调整余额</button>
                </div>
                {{#if (eq this.balanceUserId u.user_id)}}
                  <div class="balance-form">
                    <input type="number" step="0.01" placeholder="金额(正数加/负数减)" value={{this.balanceAmount}} {{on "input" this.updateBalanceAmount}} />
                    <input type="text" placeholder="备注" value={{this.balanceRemark}} {{on "input" this.updateBalanceRemark}} />
                    <button class="btn btn-small btn-primary" type="button" {{on "click" this.saveBalance}}>确认</button>
                  </div>
                {{/if}}
              </div>
            {{/each}}
          </div>
          <div class="credit-pagination">
            <span>共 {{this.usersTotal}} 个用户</span>
          </div>
        {{/if}}

      {{/if}}
    </div>
  </template>
}

export default RouteTemplate(<template><CreditAdminPage /></template>);
