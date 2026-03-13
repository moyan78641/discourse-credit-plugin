import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";

export default class CreditTipButton extends Component {
  @service currentUser;

  @action
  tipUser() {
    const post = this.args.post;
    const tipType = post.post_number === 1 ? "topic" : "comment";
    showTipModal(post.user_id, post.id, tipType);
  }

  <template>
    <DButton
      class="post-action-menu__credit-tip credit-tip-btn"
      ...attributes
      @action={{this.tipUser}}
      @icon="coins"
      @translatedTitle="打赏积分"
    />
  </template>
}

function showTipModal(targetUserId, postId, tipType) {
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
          <input type="password" id="tip-pay-key" maxlength="6"
            placeholder="6位数字支付密码" />
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
    doTip(targetUserId, postId, tipType, overlay);
  });
}

async function doTip(targetUserId, postId, tipType, overlay) {
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
      data: { target_user_id: targetUserId, amount, pay_key: payKey, tip_type: tipType, post_id: postId },
    });

    if (errorEl) errorEl.style.display = "none";
    if (successEl) {
      let msg = `打赏成功！对方收到 ${result.amount} 积分`;
      if (result.fee_amount > 0) msg += `，手续费 ${result.fee_amount}（共扣 ${result.total_deduct}）`;
      successEl.textContent = msg;
      successEl.style.display = "block";
    }
    if (btn) { btn.textContent = "完成"; }

    // 播放金币飘散动画
    showTipCelebration(postId);

    // 刷新帖子的打赏信息
    if (window.__creditRefreshTipInfo) {
      window.__creditRefreshTipInfo(postId);
    }

    setTimeout(() => overlay?.remove(), 1500);
  } catch (e) {
    const msg = e.jqXHR?.responseJSON?.error || "打赏失败";
    if (errorEl) { errorEl.textContent = msg; errorEl.style.display = "block"; }
    if (btn) { btn.disabled = false; btn.textContent = "确认打赏"; }
  }
}

// 金币飘散庆祝动画
function showTipCelebration(postId) {
  const article = document.querySelector(`article[data-post-id="${postId}"]`);
  if (!article) return;

  const tipBtn = article.querySelector(".post-action-menu__credit-tip");
  const rect = tipBtn ? tipBtn.getBoundingClientRect() : article.getBoundingClientRect();

  const emojis = ["💰", "🪙", "✨", "💎", "⭐"];
  const count = 10;

  for (let i = 0; i < count; i++) {
    const particle = document.createElement("div");
    particle.className = "credit-tip-particle";
    particle.textContent = emojis[Math.floor(Math.random() * emojis.length)];

    // 从按钮位置出发
    particle.style.left = `${rect.left + rect.width / 2 + (Math.random() - 0.5) * 20}px`;
    particle.style.top = `${rect.top + window.scrollY}px`;

    // 随机飘散方向
    const angle = Math.random() * Math.PI * 2;
    const distance = 60 + Math.random() * 80;
    particle.style.setProperty("--tx", `${Math.cos(angle) * distance}px`);
    particle.style.setProperty("--ty", `${-Math.abs(Math.sin(angle) * distance) - 20}px`);
    particle.style.animationDelay = `${Math.random() * 0.2}s`;

    document.body.appendChild(particle);
    setTimeout(() => particle.remove(), 1500);
  }
}

export { showTipModal };
