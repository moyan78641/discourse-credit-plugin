import { withPluginApi } from "discourse/lib/plugin-api";
import CreditTipButton from "../components/credit-tip-button";

export default {
  name: "credit-tip-button",

  initialize() {
    withPluginApi("1.34.0", (api) => {
      api.registerValueTransformer(
        "post-menu-buttons",
        ({ value: dag, context: { post, firstButtonKey } }) => {
          // 不给自己的帖子显示打赏按钮
          if (post.user_id === api.getCurrentUser()?.id) return;

          dag.add("credit-tip", CreditTipButton, {
            before: firstButtonKey,
          });
        }
      );
    });
  },
};
