import RouteTemplate from "ember-route-template";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

class CreditRedEnvelopeDetailPage extends Component {
  @tracked envelope = null;
  @tracked loading = true;
  @tracked error = null;
  @tracked claiming = false;
  @tracked claimResult = null;

  constructor() {
    super(...arguments);
    this.loadEnvelope();
  }

  get envelopeId() {
    const path = window.location.pathname;
    const match = path.match(/\/credit\/redenvelope\/(\d+)/);
    return match ? match[1] : null;
  }

  async loadEnvelope() {
    try {
      const data = await ajax(`/credit/redenvelope/${this.envelopeId}.json`);
      this.envelope = data;
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "加载失败";
    } finally {
      this.loading = false;
    }
  }

  @action async claimEnvelope() {
    this.claiming = true;
    this.error = null;
    try {
      const data = await ajax("/credit/redenvelope/claim.json", {
        type: "POST",
        data: { id: this.envelopeId },
      });
      this.claimResult = data;
      await this.loadEnvelope();
    } catch (e) {
      this.error = e.jqXHR?.responseJSON?.error || "领取失败";
    } finally {
      this.claiming = false;
    }
  }

  <template>
    <div class="credit-redenvelope-detail-page">
      <a href="/credit/redenvelope" class="btn btn-small btn-default credit-back-btn">← 返回红包</a>

      {{#if this.loading}}
        <p class="loading-text">加载中...</p>
      {{else if this.error}}
        <div class="credit-error">{{this.error}}</div>
      {{else if this.envelope}}
        <div class="redenvelope-card">
          <div class="re-header">
            <h2>🧧 {{this.envelope.sender_username}} 的红包</h2>
            <p class="re-message">{{this.envelope.message}}</p>
          </div>

          <div class="re-stats">
            <span>总金额: {{this.envelope.total_amount}}</span>
            <span>剩余: {{this.envelope.remaining_amount}}</span>
            <span>{{this.envelope.total_count}} 个 / 剩 {{this.envelope.remaining_count}} 个</span>
            <span>类型: {{this.envelope.type}}</span>
            <span>状态: {{this.envelope.status}}</span>
          </div>

          {{#if this.claimResult}}
            <div class="credit-success">🎉 领取成功！获得 {{this.claimResult.amount}} 积分</div>
          {{/if}}

          {{#if this.envelope.has_claimed}}
            <div class="re-my-claim">您已领取 {{this.envelope.my_amount}} 积分</div>
          {{else if this.canClaim}}
            <button class="btn btn-primary" type="button" disabled={{this.claiming}} {{on "click" this.claimEnvelope}}>
              {{if this.claiming "领取中..." "🧧 领取红包"}}
            </button>
          {{/if}}

          {{#if this.envelope.claims.length}}
            <div class="re-claims">
              <h3>领取记录</h3>
              {{#each this.envelope.claims as |claim|}}
                <div class="re-claim-row">
                  <span>{{claim.username}}</span>
                  <span class="claim-amount">{{claim.amount}}</span>
                </div>
              {{/each}}
            </div>
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}

Object.defineProperty(CreditRedEnvelopeDetailPage.prototype, "canClaim", {
  get() {
    return this.envelope && this.envelope.status === "active" && !this.envelope.has_claimed && this.envelope.remaining_count > 0;
  },
});

export default RouteTemplate(<template><CreditRedEnvelopeDetailPage /></template>);
