import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

export default apiInitializer("1.0", (api) => {
  // 编辑器工具栏：添加红包选项
  api.addComposerToolbarPopupMenuOption({
    icon: "gift",
    translatedLabel: "发红包",
    action: (toolbarEvent) => {
      showRedEnvelopeModal(toolbarEvent);
    },
  });

  // post-stream 刷新时重新处理红包
  api.onAppEvent("post-stream:refresh", () => {
    processRedEnvelopes();
  });

  // 渲染帖子中的红包卡片
  // 使用 afterAdopt: true 确保在 Ember 完成 DOM 渲染后执行
  api.decorateCookedElement(
    (elem) => {
      processRedEnvelopesInElement(elem);
    },
    { id: "credit-red-envelope-card", afterAdopt: true }
  );

  // 话题/帖子创建后绑定红包到话题
  // Discourse 在帖子创建后触发多种事件，我们监听几个常见的
  api.onAppEvent("topic:created", (post) => {
    if (post) bindEnvelopesToTopic(post);
  });
  api.onAppEvent("composer:created-post", (post) => {
    if (post) bindEnvelopesToTopic(post);
  });
  api.onAppEvent("post:created", (post) => {
    if (post) bindEnvelopesToTopic(post);
  });

  // 备用方案：用 MutationObserver 监听 post-stream 容器
  // 当 Ember 重新渲染 cooked 内容时，重新处理红包
  api.onPageChange(() => {
    scheduleRedEnvelopeProcessing();
  });
});

let _processingScheduled = false;
function scheduleRedEnvelopeProcessing() {
  if (_processingScheduled) return;
  _processingScheduled = true;
  // 等 Ember 渲染完成
  requestAnimationFrame(() => {
    setTimeout(() => {
      _processingScheduled = false;
      processRedEnvelopes();
    }, 300);
  });
}

function processRedEnvelopes() {
  const container = document.querySelector(".post-stream") || document.querySelector(".topic-post");
  if (!container) return;
  const cookedElements = container.querySelectorAll(".cooked");
  cookedElements.forEach((elem) => processRedEnvelopesInElement(elem));
}

function processRedEnvelopesInElement(elem) {
  if (!elem) return;

  // 方法1: 查找已有的 wrap div
  elem.querySelectorAll(".credit-red-envelope-wrap, [class*='credit-red-envelope-']").forEach((el) => {
    const envelopeId = el.dataset?.envelopeId || el.className.match(/credit-red-envelope-(\d+)/)?.[1];
    if (!envelopeId || el.dataset.rendered) return;
    el.dataset.rendered = "1";
    loadAndRenderEnvelope(el, envelopeId);
  });

  // 方法2: 扫描文本节点，找 [credit-red-envelope id=xxx]
  const walker = document.createTreeWalker(elem, NodeFilter.SHOW_TEXT, null, false);
  const textNodes = [];
  let node;
  while ((node = walker.nextNode())) {
    if (/\[credit-red-envelope\s+id=\d+\]/.test(node.textContent)) {
      textNodes.push(node);
    }
  }

  textNodes.forEach((textNode) => {
    const text = textNode.textContent;
    const regex = /\[credit-red-envelope\s+id=(\d+)\]/g;
    let match;
    const parts = [];
    let lastIndex = 0;

    while ((match = regex.exec(text)) !== null) {
      if (match.index > lastIndex) {
        parts.push(document.createTextNode(text.slice(lastIndex, match.index)));
      }
      const div = document.createElement("div");
      div.className = "credit-re-placeholder";
      div.dataset.envelopeId = match[1];
      div.dataset.rendered = "1";
      div.textContent = "🧧 加载红包中...";
      parts.push(div);
      lastIndex = regex.lastIndex;
    }

    if (parts.length === 0) return;

    if (lastIndex < text.length) {
      parts.push(document.createTextNode(text.slice(lastIndex)));
    }

    const parent = textNode.parentNode;
    parts.forEach((p) => parent.insertBefore(p, textNode));
    parent.removeChild(textNode);

    parent.querySelectorAll(".credit-re-placeholder").forEach((el) => {
      const eid = el.dataset.envelopeId;
      if (eid) loadAndRenderEnvelope(el, eid);
    });
  });

  // 方法3: 检查是否在 <p> 或 <code> 等标签内，文本被 HTML 包裹
  // 例如 <p>[credit-red-envelope id=4]</p>
  elem.querySelectorAll("p, span, code").forEach((el) => {
    if (el.dataset.reProcessed) return;
    const match = el.textContent.match(/^\s*\[credit-red-envelope\s+id=(\d+)\]\s*$/);
    if (match) {
      el.dataset.reProcessed = "1";
      const div = document.createElement("div");
      div.className = "credit-re-placeholder";
      div.dataset.envelopeId = match[1];
      div.dataset.rendered = "1";
      div.textContent = "🧧 加载红包中...";
      el.replaceWith(div);
      loadAndRenderEnvelope(div, match[1]);
    }
  });
}

async function bindEnvelopesToTopic(post) {
  // 从帖子内容中提取红包 ID
  let raw = post.raw || post.get?.("raw") || "";

  // 如果 raw 为空，尝试从 composer 获取
  if (!raw) {
    const composer = document.querySelector(".d-editor-input");
    if (composer) raw = composer.value || "";
  }

  const topicId = post.topic_id || post.get?.("topic_id");
  const postId = post.id || post.get?.("id");
  if (!topicId || !raw) return;

  const regex = /\[credit-red-envelope\s+id=(\d+)\]/g;
  let match;
  while ((match = regex.exec(raw)) !== null) {
    try {
      await ajax("/credit/redenvelope/bind-post.json", {
        type: "POST",
        data: {
          envelope_id: match[1],
          topic_id: topicId,
          post_id: postId,
        },
      });
    } catch {
      // ignore bind errors
    }
  }
}

function showRedEnvelopeModal(toolbarEvent) {
  document.getElementById("credit-re-overlay")?.remove();

  const overlay = document.createElement("div");
  overlay.id = "credit-re-overlay";
  overlay.className = "credit-modal-overlay";
  overlay.innerHTML = `
    <div class="credit-modal credit-re-modal" onclick="event.stopPropagation()">
      <h3>🧧 发红包</h3>
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
          <input type="number" id="re-count" min="1" max="100" value="10" placeholder="个数" />
        </div>
        <div class="form-row">
          <label>祝福语</label>
          <input type="text" id="re-message" maxlength="50" placeholder="恭喜发财，大吉大利" />
        </div>
        <div class="form-row">
          <label>领取条件</label>
          <div class="re-conditions">
            <label><input type="checkbox" id="re-require-reply" /> 需要回复</label>
            <label><input type="checkbox" id="re-require-like" /> 需要点赞</label>
          </div>
        </div>
        <div class="form-row">
          <label>回复指定内容（选填）</label>
          <input type="text" id="re-require-keyword" maxlength="100" placeholder="留空则不限制回复内容" />
        </div>
        <div class="form-row">
          <label>支付密码</label>
          <input type="password" id="re-pay-key" maxlength="6" placeholder="6位数字支付密码" />
        </div>
        <div id="re-error" class="credit-error" style="display:none"></div>
      </div>
      <div class="credit-modal-actions">
        <button class="btn btn-default" id="re-cancel-btn" type="button">取消</button>
        <button class="btn btn-primary" id="re-confirm-btn" type="button">确认发送</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) overlay.remove();
  });
  document.getElementById("re-cancel-btn").addEventListener("click", () => overlay.remove());
  document.getElementById("re-confirm-btn").addEventListener("click", () => {
    createRedEnvelope(toolbarEvent, overlay);
  });
}

async function createRedEnvelope(toolbarEvent, overlay) {
  const type = document.getElementById("re-type")?.value || "random";
  const amount = document.getElementById("re-amount")?.value;
  const count = document.getElementById("re-count")?.value;
  const message = document.getElementById("re-message")?.value || "";
  const requireReply = document.getElementById("re-require-reply")?.checked || false;
  const requireLike = document.getElementById("re-require-like")?.checked || false;
  const requireKeyword = document.getElementById("re-require-keyword")?.value || "";
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

  const btn = document.getElementById("re-confirm-btn");
  if (btn) { btn.disabled = true; btn.textContent = "发送中..."; }

  try {
    const result = await ajax("/credit/redenvelope/create.json", {
      type: "POST",
      data: { type, amount, count, message, require_reply: requireReply, require_like: requireLike, require_keyword: requireKeyword, pay_key: payKey },
    });

    const tag = `\n[credit-red-envelope id=${result.id}]\n`;
    toolbarEvent.addText(tag);
    overlay.remove();
  } catch (e) {
    const msg = e.jqXHR?.responseJSON?.error || "创建失败";
    if (errorEl) { errorEl.textContent = msg; errorEl.style.display = "block"; }
    if (btn) { btn.disabled = false; btn.textContent = "确认发送"; }
  }
}

async function loadAndRenderEnvelope(el, envelopeId) {
  try {
    const data = await ajax(`/credit/redenvelope/${envelopeId}.json`);
    renderEnvelopeCard(el, data);
  } catch {
    el.innerHTML = `<div class="credit-re-card error">红包加载失败</div>`;
  }
}

function renderEnvelopeCard(el, data) {
  const isExhausted = data.remaining_count <= 0 || data.status !== "active";
  const isExpired = data.status === "expired";
  const hasClaimed = data.has_claimed;
  const typeLabel = data.type === "random" ? "拼手气红包" : "均分红包";
  const statusClass = isExhausted ? "exhausted" : hasClaimed ? "claimed" : "active";

  let statusText = "";
  if (isExpired) statusText = "红包已过期";
  else if (isExhausted) statusText = "红包已被抢完";
  else if (hasClaimed) statusText = `你领取了 ${data.my_amount} 积分`;

  const progressPct = data.total_count > 0
    ? ((data.total_count - data.remaining_count) / data.total_count * 100).toFixed(1)
    : 0;

  let condBadges = "";
  if (data.require_reply) condBadges += '<span class="re-reply-badge">需回复</span>';
  if (data.require_like) condBadges += '<span class="re-reply-badge">需点赞</span>';
  if (data.require_keyword) condBadges += `<span class="re-reply-badge">需含「${esc(data.require_keyword)}」</span>`;

  let html = `
    <div class="credit-re-card ${statusClass}">
      <div class="re-card-header">
        <span class="re-card-icon">🧧</span>
        <span class="re-card-title">${esc(data.sender_username)} 的${typeLabel}</span>
        ${condBadges}
      </div>
      ${data.message ? `<div class="re-card-message">${esc(data.message)}</div>` : ''}
      <div class="re-card-stats">
        <div class="re-stat"><span class="re-stat-label">红包</span><span class="re-stat-value">${data.total_count - data.remaining_count}/${data.total_count}</span></div>
        <div class="re-stat"><span class="re-stat-label">积分</span><span class="re-stat-value">${(data.total_amount - data.remaining_amount).toFixed(2)}/${data.total_amount.toFixed(2)}</span></div>
      </div>
      <div class="re-card-progress"><div class="re-card-progress-bar" style="width: ${progressPct}%"></div></div>`;

  if (statusText) html += `<div class="re-card-status ${statusClass}">${statusText}</div>`;
  if (!isExhausted && !hasClaimed && !isExpired) {
    html += `<button class="btn btn-primary re-claim-btn" data-envelope-id="${data.id}">🧧 抢红包</button>`;
  }
  if (data.claims && data.claims.length > 0) {
    html += `<div class="re-card-claims">`;
    data.claims.forEach((c) => {
      html += `<div class="re-claim-row"><span>@${esc(c.username)}</span><span class="re-claim-amount">${c.amount.toFixed(2)}</span></div>`;
    });
    html += `</div>`;
  }
  html += `</div>`;
  el.innerHTML = html;

  const claimBtn = el.querySelector(".re-claim-btn");
  if (claimBtn) {
    claimBtn.addEventListener("click", async () => {
      claimBtn.disabled = true;
      claimBtn.textContent = "领取中...";
      try {
        await ajax("/credit/redenvelope/claim.json", { type: "POST", data: { id: data.id } });
        loadAndRenderEnvelope(el, data.id);
      } catch (e) {
        const msg = e.jqXHR?.responseJSON?.error || "领取失败";
        claimBtn.textContent = msg;
        setTimeout(() => { claimBtn.textContent = "🧧 抢红包"; claimBtn.disabled = false; }, 2000);
      }
    });
  }
}

function esc(str) {
  const d = document.createElement("div");
  d.textContent = str || "";
  return d.innerHTML;
}
