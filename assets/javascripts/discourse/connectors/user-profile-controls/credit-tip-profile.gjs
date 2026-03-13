import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";

export default class CreditTipProfile extends Component {
  @service currentUser;

  get shouldShow() {
    const model = this.args.outletArgs?.model;
    return model && this.currentUser && model.id !== this.currentUser.id;
  }

  @action
  tipUser() {
    const model = this.args.outletArgs?.model;
    if (!model) return;
    showProfileTipModal(model.id);
  }

  <template>
    {{#if this.shouldShow}}
      <DButton
        class="btn btn-primary credit-profile-tip-btn"
        @action={{this.tipUser}}
        @icon="coins"
        @translatedLabel="打赏"
      />
    {{/if}}
  </template>
}

function showProfileTipModal(targetUserId) {
  document.getElementById("credit-tip-overlay")?.remove();

  const overlay = document.createElement("div");
  overlay.id = "credit-tip-overlay";
  overlay.className = "credit-modal-overlay";
  overlay.innerHTML = `
    <div class="credit-modal" onclick="event.stopPropagation()">
      <h3>💰 打赏积分</h3>
      <div class="credit-tip-modal-form">
        <div class="form-row">
          <label>打赏金额</label>
          <input type="number" id="tip-amount" min="1" step="1" placeholder="输入积分数量" />
        </div>
        <div class="form-row">
          <label>支付密码</label>
          <input type="password" id="tip-pay-key" maxlength="6" placeholder="6位数字支付密码" />
        </div>
        <div id="tip-error" class="credit-error" style="display:none"></div>
        <div id="tip-success" class="credit-success" style="display:none"></div>
      </div>
      <div class="credit-modal-actions">
        <button class="btn btn-default" id="tip-cancel-btn" type="button">取消</button>
        <button class="btn btn-primary" id="tip-confirm-btn" type="button">确认打赏</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) overlay.remove();
  });
  document.getElementById("tip-cancel-btn").addEventListener("click", () => overlay.remove());
  document.getElementById("tip-confirm-btn").addEventListener("click", () => {
    doProfileTip(targetUserId, overlay);
  });
}

async function doProfileTip(targetUserId, overlay) {
  const amount = document.getElementById("tip-amount")?.value;
  const payKey = document.getElementById("tip-pay-key")?.value;
  const errorEl = document.getElementById("tip-error");
  const successEl = document.getElementById("tip-success");
  const btn = document.getElementById("tip-confirm-btn");

  if (!amount || parseFloat(amount) <= 0) {
    if (errorEl) { errorEl.textContent = "请输入有效金额"; errorEl.style.display = "block"; }
    return;
  }
  if (!payKey || payKey.length !== 6) {
    if (errorEl) { errorEl.textContent = "请输入6位支付密码"; errorEl.style.display = "block"; }
    return;
  }

  if (btn) { btn.disabled = true; btn.textContent = "打赏中..."; }

  try {
    const result = await ajax("/credit/tip.json", {
      type: "POST",
      data: { target_user_id: targetUserId, amount, pay_key: payKey, tip_type: "profile" },
    });

    if (errorEl) errorEl.style.display = "none";
    if (successEl) {
      let msg = `打赏成功！对方收到 ${result.amount} 积分`;
      if (result.fee_amount > 0) msg += `，手续费 ${result.fee_amount}（共扣 ${result.total_deduct}）`;
      successEl.textContent = msg;
      successEl.style.display = "block";
    }
    if (btn) { btn.textContent = "完成"; }
    setTimeout(() => overlay?.remove(), 1500);
  } catch (e) {
    const msg = e.jqXHR?.responseJSON?.error || "打赏失败";
    if (errorEl) { errorEl.textContent = msg; errorEl.style.display = "block"; }
    if (btn) { btn.disabled = false; btn.textContent = "确认打赏"; }
  }
}
