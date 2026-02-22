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

      // 帖子下方显示打赏信息
      api.decorateCookedElement(
        (elem, helper) => {
          if (!helper) return;
          const post = helper.getModel();
          if (!post || !post.id) return;

          const parent = elem.parentElement;
          if (!parent) return;
          if (parent.querySelector(".credit-tip-info")) return;

          loadAndRenderTipInfo(post.id, parent);
        },
        { id: "credit-tip-info" }
      );
    });
  },
};

async function loadAndRenderTipInfo(postId, parentEl) {
  try {
    const data = await ajax(`/credit/tip/post/${postId}.json`);
    if (!data || data.count === 0) return;
    renderTipInfo(data, parentEl, postId);
  } catch {
    // ignore
  }
}

function renderTipInfo(data, parentEl, postId) {
  const container = document.createElement("div");
  container.className = "credit-tip-info";
  container.dataset.postId = postId;

  // 收起状态：💰 图标 + 前几个小头像 + 总金额
  const previewAvatars = data.tips.slice(0, 5);
  let previewHtml = "";
  previewAvatars.forEach((t) => {
    const url = t.avatar_template ? t.avatar_template.replace("{size}", "20") : "";
    previewHtml += `<img class="tip-preview-avatar" src="${url}" width="20" height="20" title="@${esc(t.username)}" loading="lazy" />`;
  });
  if (data.count > 5) {
    previewHtml += `<span class="tip-preview-more">+${data.count - 5}</span>`;
  }

  // 展开状态：每行一个打赏人
  let detailHtml = "";
  data.tips.forEach((t) => {
    const url = t.avatar_template ? t.avatar_template.replace("{size}", "25") : "";
    detailHtml += `
      <div class="tip-detail-row">
        <a href="/u/${esc(t.username)}" class="tip-detail-avatar">
          <img src="${url}" width="25" height="25" loading="lazy" />
        </a>
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

  // 点击切换展开/收起
  const summaryRow = container.querySelector(".tip-summary-row");
  const detailPanel = container.querySelector(".tip-detail-panel");
  summaryRow.addEventListener("click", () => {
    const isOpen = detailPanel.style.display !== "none";
    detailPanel.style.display = isOpen ? "none" : "block";
    container.classList.toggle("expanded", !isOpen);
  });

  parentEl.appendChild(container);
}

function esc(str) {
  const d = document.createElement("div");
  d.textContent = str || "";
  return d.innerHTML;
}

// 供 credit-tip-button.gjs 打赏成功后刷新用
window.__creditRefreshTipInfo = async function (postId) {
  const postEl = document.querySelector(`article[data-post-id="${postId}"]`);
  if (!postEl) return;
  const oldInfo = postEl.querySelector(".credit-tip-info");
  if (oldInfo) oldInfo.remove();

  try {
    const data = await ajax(`/credit/tip/post/${postId}.json`);
    if (!data || data.count === 0) return;
    const cookedParent = postEl.querySelector(".cooked")?.parentElement;
    if (cookedParent) renderTipInfo(data, cookedParent, postId);
  } catch {
    // ignore
  }
};
