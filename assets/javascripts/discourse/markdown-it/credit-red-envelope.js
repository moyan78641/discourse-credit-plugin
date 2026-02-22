// Discourse Markdown-it 扩展：解析 [credit-red-envelope id=xxx] 标记
export function setup(helper) {
  helper.registerOptions((opts, siteSettings) => {
    opts.features["credit-red-envelope"] = !!siteSettings.credit_enabled;
  });

  helper.allowList({
    custom(tag, name, value) {
      if (tag === "div" && name === "data-envelope-id") return true;
      if (tag === "div" && name === "class" && value === "credit-red-envelope-wrap") return true;
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

      const openToken = state.push("credit_red_envelope_open", "div", 1);
      openToken.attrs = [
        ["class", "credit-red-envelope-wrap"],
        ["data-envelope-id", envelopeId],
      ];
      openToken.map = [startLine, startLine + 1];

      const closeToken = state.push("credit_red_envelope_close", "div", -1);

      state.line = startLine + 1;
      return true;
    });
  });
}
