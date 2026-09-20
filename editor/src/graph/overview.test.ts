import { describe, expect, it } from "vitest";
import type { BgalsOverview } from "../../shared/overview";
import { buildOverviewFlow, statsLine } from "./overview";

function overview(partial: Partial<BgalsOverview> = {}): BgalsOverview {
  return {
    format: "bgals-overview/1",
    compiler: "test",
    begin: "a",
    scripts: [
      { name: "a", dialogues: 13, insts: 6, options: 1, conds: 1, jumps: 2 },
      { name: "b", dialogues: 5, insts: 6, options: 0, conds: 0, jumps: 1 },
    ],
    edges: [
      { from: "a", to: "b", kind: "jump" },
      { from: "a", to: "main_menu", kind: "jump" },
      { from: "b", to: "ghost_x", kind: "jump" },
    ],
    missing: ["ghost_x"],
    ...partial,
  };
}

describe("buildOverviewFlow", () => {
  it("剧本/begin/终态/幽灵节点映射", () => {
    const { nodes, edges } = buildOverviewFlow(overview());
    const byId = new Map(nodes.map((n) => [n.id, n]));
    expect(byId.get("a")).toMatchObject({ type: "script", data: { begin: true } });
    expect(byId.get("b")).toMatchObject({ type: "script", data: { begin: false } });
    expect(byId.get("main_menu")).toMatchObject({ type: "terminal", data: { terminal: true } });
    expect(byId.get("ghost_x")).toMatchObject({ type: "ghost", data: { ghost: true } });
    expect(edges).toHaveLength(3);
  });

  it("无 main_menu 边时不产生终态节点；missing 为空无幽灵", () => {
    const { nodes } = buildOverviewFlow(
      overview({ edges: [{ from: "a", to: "b", kind: "jump" }], missing: [] }),
    );
    expect(nodes.some((n) => n.id === "main_menu")).toBe(false);
    expect(nodes.some((n) => n.data.ghost)).toBe(false);
  });

  it("dagre LR 布局：begin 在最左列，下游 x 严格更大", () => {
    const { nodes } = buildOverviewFlow(overview());
    const byId = new Map(nodes.map((n) => [n.id, n.position]));
    expect(byId.get("b")!.x).toBeGreaterThan(byId.get("a")!.x);
    expect(byId.get("ghost_x")!.x).toBeGreaterThan(byId.get("b")!.x);
  });

  it("悬空边（端点不在节点集）被丢弃", () => {
    const { edges } = buildOverviewFlow(
      overview({ edges: [{ from: "a", to: "nowhere", kind: "jump" }], missing: [] }),
    );
    expect(edges).toHaveLength(0);
  });
});

describe("statsLine", () => {
  it("非零项拼接，零值省略", () => {
    expect(statsLine({ name: "a", dialogues: 13, insts: 6, options: 1, conds: 1, jumps: 2 })).toBe(
      "13 对话 · 6 指令 · 1 选项 · 1 分支 · 2 跳转",
    );
    expect(statsLine({ name: "b", dialogues: 5, insts: 6, options: 0, conds: 0, jumps: 1 })).toBe(
      "5 对话 · 6 指令 · 1 跳转",
    );
    expect(statsLine({ name: "e", dialogues: 0, insts: 0, options: 0, conds: 0, jumps: 0 })).toBe(
      "空剧本",
    );
  });
});
