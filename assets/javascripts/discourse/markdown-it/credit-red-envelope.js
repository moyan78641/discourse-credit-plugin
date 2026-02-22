// Discourse Markdown-it 扩展：解析 [credit-red-envelope id=xxx] 标记
export function setup(helper) {
  helper.registerOptions((opts, siteSettings) => {
    opts.features["credit-red-envelope"] = !!siteSettings.credit_enabled;
  });

  helper.allowList(["div.credit-red-envelope-wrap", "div[data-envelope-id]"]);

  helper.registerPlugin((md) => {
    md.block.ruler.before("paragraph", "credit_red_envelope", (state, startLine, endLine, silent) => {
      const line = state.src.slice(state.bMarks[startLine] + state.tShift[startLine], state.eMarks[startLine]).trim();
      const match = line.match(/^\[credit-red-envelope\s+id=(\d+)\]$/);
      if (!match) return false;
      if (silent) return true;

      const token = state.push("credit_red_envelope", "div", 0);
      token.attrs = [
        ["class", "credit-red-envelope-wrap"],
        ["data-envelope-id", match[1]],
      ];
      token.map = [startLine, startLine + 1];
      state.line = startLine + 1;
      return true;
    });

    md.renderer.rules.credit_red_envelope = (tokens, idx) => {
      const token = tokens[idx];
      const id = token.attrGet("data-envelope-id");
      return `<div class="credit-red-envelope-wrap" data-envelope-id="${id}">加载红包中...</div>`;
    };
  });
}
