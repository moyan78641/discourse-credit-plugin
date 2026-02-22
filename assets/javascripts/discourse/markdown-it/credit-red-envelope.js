// Discourse Markdown-it 扩展：解析 [credit-red-envelope id=xxx] 标记
// 用 class 名嵌入 ID（credit-red-envelope-{id}），避免 data-* 被 sanitizer 清掉
export function setup(helper) {
  helper.registerOptions((opts, siteSettings) => {
    opts.features["credit-red-envelope"] = !!siteSettings.credit_enabled;
  });

  // allowList class 名（用正则匹配 credit-red-envelope-xxx）
  helper.allowList({
    custom(tag, name, value) {
      if (tag === "div" && name === "class" && /credit-red-envelope-\d+/.test(value)) return true;
      return false;
    },
  });

  helper.registerPlugin((md) => {
    md.block.ruler.before("paragraph", "credit_red_envelope", (state, startLine, endLine, silent) => {
      const pos = state.bMarks[startLine] + state.tShift[startLine];
      const max = state.eMarks[startLine];
      const line = state.src.slice(pos, max).trim();

      const match = line.match(/^\[credit-red-envelope\s+id=(\d+)\]$/);
      if (!match) return false;
      if (silent) return true;

      const envelopeId = match[1];

      // 用 open+close token 生成 <div class="credit-red-envelope-{id}"></div>
      const openToken = state.push("credit_re_open", "div", 1);
      openToken.attrs = [["class", `credit-red-envelope-${envelopeId}`]];
      openToken.map = [startLine, startLine + 1];

      state.push("credit_re_close", "div", -1);
      state.line = startLine + 1;
      return true;
    });
  });
}
