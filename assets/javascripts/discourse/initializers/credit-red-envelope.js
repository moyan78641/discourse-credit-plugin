import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

export default apiInitializer("1.0", (api) => {
  // 编辑器工具栏：添加红包选项
  api.addComposerToolbarPopupMenuOption({
    icon: "gift",
    label: "发红包",
    action: (toolbarEvent) => {
      const controller = api.container.lookup("controller:composer");
      showRedEnvelopeModal(api, toolbarEvent, controller);
    },
  });

  // 渲染帖子中的红包卡片
  api.decorateCookedElement(
    (elem, helper) => {
      if (!helper) return;
      const envelopes = elem.querySelectorAll(".credit-red-envelope-wrap");
      envelopes.forEach((el) => {
        const envelopeId = el.dataset.envelopeId;
        if (!envelopeId) return;
        loadAndRenderEnvelope(el, envelopeId, api);
      });
    },
    { id: "credit-red-envelope-card" }
  );
});

function showRedEnvelopeModal(api, toolbarEvent) {
  const dialog = api.container.lookup("service:dialog");

  // 创建弹窗内容
  const html = `
    <div class="credit-re-modal-form">
      <div class="form-row">
        <label>红包类型</label>
        <select id="re-type">
          <option value="random">拼手气红包</option>
          <option value="fixed">均分红包</option>
        </select>
      </div>
      <div class="form-row">
        <label>总金额</label>
        <input type="number" id="re-amount" min="0.01" step="0.01" placeholder="输入总金额" />
      </div>
      <div class="form-row">
        <label>红包个数</label>
        <input type="number" id="re-count" min="1" max="100" placeholder="输入个数" value="10" />
      </div>
      <div class="form-row">
        <label>祝福语</label>
        <input type="text" id="re-message" maxlength="50" placeholder="恭喜发财，大吉大利" />
      </div>
      <div class="form-row">
        <label><input type="checkbox" id="re-require-reply" /> 需要回复后才能领取</label>
      </div>
      <div class="form-row">
        <label>支付密码</label>
        <input type="password" id="re-pay-key" maxlength="6" placeholder="6位数字支付密码" />
      </div>
      <div id="re-error" class="credit-error" style="display:none"></div>
    </div>
  `;

  dialog.alert({
    title: "🧧 发红包",
    rawHtml: html,
    buttons: [
      {
        label: "确认发送",
        class: "btn-primary",
        action: () => createRedEnvelope(toolbarEvent),
      },
      {
        label: "取消",
        class: "btn-default",
      },
    ],
  });
}

async function createRedEnvelope(toolbarEvent) {
  const type = document.getElementById("re-type")?.value || "random";
  const amount = document.getElementById("re-amount")?.value;
  const count = document.getElementById("re-count")?.value;
  const message = document.getElementById("re-message")?.value || "";
  const requireReply = document.getElementById("re-require-reply")?.checked || false;
  const payKey = document.getElementById("re-pay-key")?.value;
  const errorEl = document.getElementById("re-error");

  if (!amount || parseFloat(amount) <= 0) {
    if (errorEl) { errorEl.textContent = "请输入有效金额"; errorEl.style.display = "block"; }
    return;
  }
  if (!payKey || payKey.length !== 6) {
    if (errorEl) { errorEl.textContent = "请输入6位支付密码"; errorEl.style.display = "block"; }
    return;
  }

  try {
    const result = await ajax("/credit/redenvelope/create.json", {
      type: "POST",
      data: { type, amount, count, message, require_reply: requireReply, pay_key: payKey },
    });

    // 插入红包标记到编辑器
    const tag = `\n[credit-red-envelope id=${result.id}]\n`;
    toolbarEvent.addText(tag);
  } catch (e) {
    const msg = e.jqXHR?.responseJSON?.error || "创建失败";
    if (errorEl) { errorEl.textContent = msg; errorEl.style.display = "block"; }
  }
}

async function loadAndRenderEnvelope(el, envelopeId, api) {
  try {
    const data = await ajax(`/credit/redenvelope/${envelopeId}.json`);
    renderEnvelopeCard(el, data, api);
  } catch {
    el.innerHTML = `<div class="credit-re-card error">红包加载失败</div>`;
  }
}

function renderEnvelopeCard(el, data, api) {
  const isExhausted = data.remaining_count <= 0 || data.status !== "active";
  const isExpired = data.status === "expired";
  const hasClaimed = data.has_claimed;
  const typeLabel = data.type === "random" ? "拼手气红包" : "均分红包";
  const statusClass = isExhausted ? "exhausted" : hasClaimed ? "claimed" : "active";

  let statusText = "";
  if (isExpired) statusText = "红包已过期";
  else if (isExhausted) statusText = "红包已被抢完";
  else if (hasClaimed) statusText = `你领取了 ${data.my_amount} 积分`;
  else statusText = "";

  const progressPct = data.total_count > 0
    ? ((data.total_count - data.remaining_count) / data.total_count * 100).toFixed(1)
    : 0;

  let html = `
    <div class="credit-re-card ${statusClass}">
      <div class="re-card-header">
        <svg class="fa d-icon d-icon-gift svg-icon svg-string" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><use href="#gift"></use></svg>
        <span class="re-card-title">${data.sender_username} 的${typeLabel}</span>
        ${data.require_reply ? '<span class="re-reply-badge">需回复</span>' : ''}
      </div>
      ${data.message ? `<div class="re-card-message">${escapeHtml(data.message)}</div>` : ''}
      <div class="re-card-stats">
        <div class="re-stat">
          <span class="re-stat-label">红包</span>
          <span class="re-stat-value">${data.total_count - data.remaining_count}/${data.total_count}</span>
        </div>
        <div class="re-stat">
          <span class="re-stat-label">积分</span>
          <span class="re-stat-value">
            <svg class="fa d-icon d-icon-bolt-lightning svg-icon svg-string" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><use href="#bolt-lightning"></use></svg>
            ${(data.total_amount - data.remaining_amount).toFixed(2)}/${data.total_amount.toFixed(2)}
          </span>
        </div>
      </div>
      <div class="re-card-progress">
        <div class="re-card-progress-bar" style="width: ${progressPct}%"></div>
      </div>`;

  if (statusText) {
    html += `<div class="re-card-status ${statusClass}">${statusText}</div>`;
  }

  if (!isExhausted && !hasClaimed && !isExpired) {
    html += `<button class="btn btn-primary re-claim-btn" data-envelope-id="${data.id}">🧧 抢红包</button>`;
  }

  // 领取记录
  if (data.claims && data.claims.length > 0) {
    html += `<div class="re-card-claims">`;
    data.claims.forEach((c) => {
      html += `<div class="re-claim-row"><span>@${escapeHtml(c.username)}</span><span class="re-claim-amount">${c.amount.toFixed(2)}</span></div>`;
    });
    html += `</div>`;
  }

  html += `</div>`;
  el.innerHTML = html;

  // 绑定抢红包按钮
  const claimBtn = el.querySelector(".re-claim-btn");
  if (claimBtn) {
    claimBtn.addEventListener("click", async () => {
      claimBtn.disabled = true;
      claimBtn.textContent = "领取中...";
      try {
        const result = await ajax("/credit/redenvelope/claim.json", {
          type: "POST",
          data: { id: data.id },
        });
        // 重新加载卡片
        loadAndRenderEnvelope(el, data.id, api);
      } catch (e) {
        const msg = e.jqXHR?.responseJSON?.error || "领取失败";
        claimBtn.textContent = msg;
        setTimeout(() => { claimBtn.textContent = "🧧 抢红包"; claimBtn.disabled = false; }, 2000);
      }
    });
  }
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
