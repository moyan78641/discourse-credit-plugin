import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import CreditTipButton from "../components/credit-tip-button";

export default apiInitializer("1.34.0", (api) => {
    // 帖子菜单添加打赏按钮
    api.registerValueTransformer(
        "post-menu-buttons",
        ({ value: dag, context: { post, firstButtonKey } }) => {
            // 未登录用户不显示打赏按钮
            const currentUser = api.getCurrentUser();
            if (!currentUser) return;
            // 不能打赏自己
            if (post.user_id === currentUser.id) return;
            // 私信中不显示打赏按钮
            if (post.topic?.archetype === "private_message") return;
            dag.add("credit-tip", CreditTipButton, {
                before: firstButtonKey,
            });
        }
    );

    // 批量加载打赏信息（decorateCookedElement 仅处理单个帖子标记）
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
            // 标记需要加载打赏信息，由批量请求统一处理
            parent.dataset.needsTipInfo = postId;
        },
        { id: "credit-tip-info", afterAdopt: true }
    );

    // 页面变化时批量加载所有帖子的打赏信息
    api.onPageChange(() => {
        // 等 Ember 渲染完成后再收集
        requestAnimationFrame(() => {
            setTimeout(() => batchLoadTips(), 300);
        });
    });
});

// 防抖标记
let _batchLoading = false;

async function batchLoadTips() {
    if (_batchLoading) return;
    _batchLoading = true;

    try {
        const articles = document.querySelectorAll("article[data-post-id]");
        const postIds = [];

        articles.forEach((article) => {
            // 跳过已有打赏信息的帖子
            if (article.querySelector(".credit-tip-info")) return;
            if (article.dataset.tipLoaded) return;
            const postId = article.dataset.postId;
            if (postId) postIds.push(postId);
        });

        if (postIds.length === 0) return;

        // 标记为正在加载，避免重复请求
        postIds.forEach((id) => {
            const article = document.querySelector(`article[data-post-id="${id}"]`);
            if (article) article.dataset.tipLoaded = "1";
        });

        // 单次批量请求获取所有帖子的打赏信息
        const data = await ajax(`/credit/tip/posts.json?${postIds.map((id) => `post_ids[]=${id}`).join("&")}`);

        // 标记当前用户的打赏状态 + 渲染打赏信息
        for (const id of postIds) {
            const article = document.querySelector(`article[data-post-id="${id}"]`);
            if (!article) continue;
            const tipData = data[id];
            if (tipData && tipData.current_user_tipped) {
                article.dataset.userTipped = "1";
            }
            if (!tipData || tipData.count === 0) continue;
            if (article.querySelector(".credit-tip-info")) continue;
            const cooked = article.querySelector(".cooked");
            if (cooked) renderTipInfo(tipData, cooked, id);
        }
    } catch {
        // 忽略错误
    } finally {
        _batchLoading = false;
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
    // 清除已加载标记，允许重新加载
    delete article.dataset.tipLoaded;
    // 打赏成功后标记当前用户已打赏
    article.dataset.userTipped = "1";

    try {
        const data = await ajax(`/credit/tip/post/${postId}.json`);
        if (!data || data.count === 0) return;
        const cooked = article.querySelector(".cooked");
        if (cooked) renderTipInfo(data, cooked, postId);
    } catch {
        // 忽略错误
    }
};
