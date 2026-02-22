import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import CreditTipButton from "../components/credit-tip-button";

export default {
  name: "credit-tip-button",

  initialize() {
    withPluginApi("1.34.0", (api) => {
      // 帖子菜单添加打赏按钮
      api.registerValueTransformer(
        "post-menu-buttons",
        ({ value: dag, context: { post, firstButtonKey } }) => {
          if (post.user_id === api.getCurrentUser()?.id) return;
          dag.add("credit-tip", CreditTipButton, {
            before: firstButtonKey,
          });
        }
      );

      // 方案1: decorateCookedElement (首次渲染)
      api.decorateCookedElement(
        (elem, helper) => {
          if (!helper) return;
          let postId = null;
          const model = helper.getModel();
          if (model?.id) {
            postId = model.id;
          } else {
            const article = elem.closest("article[data-post-id]");
            if (article) postId = article.dataset.postId;
          }
          if (!postId) return;
          const parent = elem.closest("article[data-post-id]") || elem.parentElement;
          if (!parent) return;
          if (parent.querySelector(".credit-tip-info")) return;
          loadAndRenderTipInfo(postId, elem);
        },
        { id: "credit-tip-info", afterAdopt: true }
      );

      // 方案2: MutationObserver 兜底
      // 监听 document.body，当新的 article[data-post-id] 出现时处理
      setupTipObserver();

      // 方案3: onPageChange 多次重试
      api.onPageChange(() => {
        // 延迟多次尝试，覆盖帖子异步加载的情况
        [500, 1500, 3000].forEach((delay) => {
          setTimeout(() => processAllTips(), delay);
        });
      });
    });
  },
};

let _observer = null;
function setupTipObserver() {
  if (_observer) return;

  _observer = new MutationObserver((mutations) => {
    let hasNewArticles = false;
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType !== 1) continue;
        // 检查是否是 article 或包含 article
        if (node.matches?.("article[data-post-id]") ||
            node.querySelector?.("article[data-post-id]")) {
          hasNewArticles = true;
          break;
        }
        // 检查是否是 .cooked 元素被添加
        if (node.matches?.(".cooked") || node.querySelector?.(".cooked")) {
          hasNewArticles = true;
          break;
        }
      }
      if (hasNewArticles) break;
    }
    if (hasNewArticles) {
      // 用 debounce 避免频繁触发
      clearTimeout(_observer._debounceTimer);
      _observer._debounceTimer = setTimeout(() => processAllTips(), 200);
    }
  });

  // 开始观察
  _observer.observe(document.body, { childList: true, subtree: true });
}

function processAllTips() {
  const articles = document.querySelectorAll("article[data-post-id]");
  articles.forEach((article) => {
    if (article.querySelector(".credit-tip-info")) return;
    // 标记正在处理，避免重复请求
    if (article.dataset.tipLoading) return;
    const postId = article.dataset.postId;
    if (!postId) return;
    const cooked = article.querySelector(".cooked");
    if (!cooked) return;
    article.dataset.tipLoading = "1";
    loadAndRenderTipInfo(postId, cooked).then(() => {
      delete article.dataset.tipLoading;
    });
  });
}

async function loadAndRenderTipInfo(postId, cookedElem) {
  try {
    const data = await ajax(`/credit/tip/post/${postId}.json`);
    if (!data || data.count === 0) return;
    // 再次检查避免重复
    const article = cookedElem.closest("article[data-post-id]");
    if (article?.querySelector(".credit-tip-info")) return;
    renderTipInfo(data, cookedElem, postId);
  } catch {
    // ignore
  }
}

function renderTipInfo(data, cookedElem, postId) {
  const container = document.createElement("div");
  container.className = "credit-tip-info";
  container.dataset.postId = postId;

  const previewAvatars = data.tips.slice(0, 5);
  let previewHtml = "";
  previewAvatars.forEach((t) => {
    const url = t.avatar_template ? t.avatar_template.replace("{size}", "20") : "";
    previewHtml += `<img class="tip-preview-avatar" src="${url}" width="20" height="20" title="@${esc(t.username)}" loading="lazy" />`;
  });
  if (data.count > 5) {
    previewHtml += `<span class="tip-preview-more">+${data.count - 5}</span>`;
  }

  let detailHtml = "";
  data.tips.forEach((t) => {
    const url = t.avatar_template ? t.avatar_template.replace("{size}", "25") : "";
    detailHtml += `
      <div class="tip-detail-row">
        <a href="/u/${esc(t.username)}" class="tip-detail-avatar"><img src="${url}" width="25" height="25" loading="lazy" /></a>
        <a href="/u/${esc(t.username)}" class="tip-detail-username">@${esc(t.username)}</a>
        <span class="tip-detail-amount">${t.amount} 积分</span>
      </div>`;
  });

  container.innerHTML = `
    <div class="tip-summary-row" role="button" tabindex="0">
      <span class="tip-summary-icon">💰</span>
      <span class="tip-summary-avatars">${previewHtml}</span>
      <span class="tip-summary-text">收到赞赏 <strong>${data.total_amount}</strong> 积分</span>
    </div>
    <div class="tip-detail-panel" style="display:none">
      <div class="tip-detail-header">赞赏明细 (${data.count}人)</div>
      ${detailHtml}
    </div>
  `;

  const summaryRow = container.querySelector(".tip-summary-row");
  const detailPanel = container.querySelector(".tip-detail-panel");
  summaryRow.addEventListener("click", () => {
    const isOpen = detailPanel.style.display !== "none";
    detailPanel.style.display = isOpen ? "none" : "block";
    container.classList.toggle("expanded", !isOpen);
  });

  if (cookedElem.parentElement) {
    cookedElem.parentElement.insertBefore(container, cookedElem.nextSibling);
  } else {
    cookedElem.appendChild(container);
  }
}

function esc(str) {
  const d = document.createElement("div");
  d.textContent = str || "";
  return d.innerHTML;
}

// 供 credit-tip-button.gjs 打赏成功后刷新用
window.__creditRefreshTipInfo = async function (postId) {
  const article = document.querySelector(`article[data-post-id="${postId}"]`);
  if (!article) return;
  const oldInfo = article.querySelector(".credit-tip-info");
  if (oldInfo) oldInfo.remove();

  try {
    const data = await ajax(`/credit/tip/post/${postId}.json`);
    if (!data || data.count === 0) return;
    const cooked = article.querySelector(".cooked");
    if (cooked) renderTipInfo(data, cooked, postId);
  } catch {
    // ignore
  }
};
