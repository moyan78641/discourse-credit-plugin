import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";

export default class CreditTipButton extends Component {
  @service dialog;
  @service currentUser;

  static hidden(args) {
    // 不给自己的帖子显示
    return args.post.user_id === args.currentUser?.id;
  }

  @action
  tipUser() {
    const post = this.args.post;
    const tipType = post.post_number === 1 ? "topic" : "comment";

    this.dialog.alert({
      title: "💰 打赏积分",
      rawHtml: `
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
      `,
      buttons: [
        {
          label: "确认打赏",
          class: "btn-primary",
          action: () => this.doTip(post.user_id, post.id, tipType),
        },
        { label: "取消", class: "btn-default" },
      ],
    });
  }

  async doTip(targetUserId, postId, tipType) {
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
        data: { target_user_id: targetUserId, amount, pay_key: payKey, tip_type: tipType, post_id: postId },
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

  <template>
    <DButton
      class="post-action-menu__credit-tip credit-tip-btn"
      ...attributes
      @action={{this.tipUser}}
      @icon="heart"
      @title="打赏积分"
    />
  </template>
}
