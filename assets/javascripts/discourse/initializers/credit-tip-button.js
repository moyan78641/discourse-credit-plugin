import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

export default apiInitializer("1.0", (api) => {
  // 帖子/评论打赏按钮
  api.addPostMenuButton("credit-tip", (attrs) => {
    // 不给自己的帖子显示打赏按钮
    if (attrs.canManage) return;

    return {
      action: "creditTip",
      icon: "heart",
      className: "credit-tip-btn",
      title: "打赏积分",
      position: "first",
    };
  });

  api.attachWidgetAction("post-menu", "creditTip", function () {
    const post = this.findAncestorModel();
    if (!post) return;

    const userId = post.user_id;
    const postId = post.id;
    const isFirstPost = post.post_number === 1;
    const tipType = isFirstPost ? "topic" : "comment";

    showTipDialog(api, userId, postId, tipType);
  });

  // 个人主页打赏按钮
  api.addUserProfileCustomAction("credit-tip-profile", {
    label: "打赏",
    icon: "hand-holding-heart",
    action(user) {
      showTipDialog(api, user.id, null, "profile");
    },
  });
});

function showTipDialog(api, targetUserId, postId, tipType) {
  const dialog = api.container.lookup("service:dialog");

  const html = `
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
  `;

  dialog.alert({
    title: "💰 打赏积分",
    rawHtml: html,
    buttons: [
      {
        label: "确认打赏",
        class: "btn-primary",
        action: () => doTip(targetUserId, postId, tipType),
      },
      { label: "取消", class: "btn-default" },
    ],
  });
}

async function doTip(targetUserId, postId, tipType) {
  const amount = document.getElementById("tip-amount")?.value;
  const payKey = document.getElementById("tip-pay-key")?.value;
  const errorEl = document.getElementById("tip-error");
  const successEl = document.getElementById("tip-success");

  if (!amount || parseFloat(amount) <= 0) {
    if (errorEl) { errorEl.textContent = "请输入有效金额"; errorEl.style.display = "block"; }
    return;
  }
  if (!payKey || payKey.length !== 6) {
    if (errorEl) { errorEl.textContent = "请输入6位支付密码"; errorEl.style.display = "block"; }
    return;
  }

  try {
    const result = await ajax("/credit/tip.json", {
      type: "POST",
      data: {
        target_user_id: targetUserId,
        amount,
        pay_key: payKey,
        tip_type: tipType,
        post_id: postId,
      },
    });

    if (errorEl) errorEl.style.display = "none";
    if (successEl) {
      let msg = `打赏成功！金额: ${result.amount}`;
      if (result.fee_amount > 0) msg += `，手续费: ${result.fee_amount}`;
      successEl.textContent = msg;
      successEl.style.display = "block";
    }
  } catch (e) {
    const msg = e.jqXHR?.responseJSON?.error || "打赏失败";
    if (errorEl) { errorEl.textContent = msg; errorEl.style.display = "block"; }
  }
}
