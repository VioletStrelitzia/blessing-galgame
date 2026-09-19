import { describe, expect, it } from "vitest";
import { resolveInlineKey } from "./inlineEdit";

describe("resolveInlineKey（行内编辑键位约定）", () => {
  it("Enter 提交", () => {
    expect(resolveInlineKey("Enter", false)).toBe("submit");
  });

  it("Shift+Enter 换行（不拦截，走 textarea 默认行为）", () => {
    expect(resolveInlineKey("Enter", true)).toBeNull();
  });

  it("Esc 取消", () => {
    expect(resolveInlineKey("Escape", false)).toBe("cancel");
    expect(resolveInlineKey("Escape", true)).toBe("cancel");
  });

  it("其余按键不拦截", () => {
    expect(resolveInlineKey("a", false)).toBeNull();
    expect(resolveInlineKey("Tab", false)).toBeNull();
    expect(resolveInlineKey("Backspace", false)).toBeNull();
  });
});
