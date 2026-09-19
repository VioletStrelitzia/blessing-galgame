import { describe, expect, it } from "vitest";
import { semanticEqual } from "./compare";
import type { BgalsGraph, DialogueNode } from "./graph";

function dlg(id: string, character = "", text = id): DialogueNode {
  return {
    id,
    kind: "dialogue",
    character,
    text,
    display_text: text,
    anchors: [],
    prev: [],
    post: [],
  };
}

function base(): BgalsGraph {
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [
      { id: "start", kind: "start" },
      dlg("a", "甲", "你好"),
      { id: "g", kind: "option_group" },
      dlg("x", "", "体内"),
      dlg("m", "", "汇合"),
      { id: "end", kind: "end" },
    ],
    edges: [
      { from: "start", to: "a", kind: "seq" },
      { from: "a", to: "g", kind: "seq" },
      { from: "g", to: "x", kind: "option", text: "去" },
      { from: "g", to: "m", kind: "option", text: "不去", cond: "f > 0" },
      { from: "x", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ],
  };
}

describe("semanticEqual", () => {
  it("剥 id / comment / 节点顺序后语义相等", () => {
    const a = base();
    // 全新 id + 追加 comment + 节点乱序 + 多余 sidecar 式差异
    const b: BgalsGraph = {
      ...a,
      nodes: [
        { id: "c9", kind: "comment", text: "注释不参与对比", before: null },
        ...[...a.nodes].reverse().map((n) => ({ ...n, id: `z_${n.id}` })),
      ],
      edges: a.edges.map((e) => ({ ...e, from: `z_${e.from}`, to: `z_${e.to}` })),
    };
    const r = semanticEqual(a, b);
    expect(r.equal).toBe(true);
    expect(r.diffs).toEqual([]);
  });

  it("对话文本变化：报节点缺失/多出", () => {
    const a = base();
    const b: BgalsGraph = {
      ...a,
      nodes: a.nodes.map((n) => (n.id === "a" ? { ...n, text: "你不好" } : n)),
    };
    const r = semanticEqual(a, b);
    expect(r.equal).toBe(false);
    expect(r.diffs.some((d) => d.includes("节点缺失") && d.includes("你好"))).toBe(true);
    expect(r.diffs.some((d) => d.includes("节点多出") && d.includes("你不好"))).toBe(true);
  });

  it("节点增删：报节点多出/缺失", () => {
    const a = base();
    const b: BgalsGraph = {
      ...a,
      nodes: [...a.nodes, dlg("extra", "", "多出来的一句")],
    };
    const r = semanticEqual(a, b);
    expect(r.diffs).toContain("节点多出：dialogue 「多出来的一句」");
  });

  it("边差异：报边缺失/多出（含端点标签）", () => {
    const a = base();
    const b: BgalsGraph = {
      ...a,
      edges: a.edges.filter((e) => !(e.from === "x" && e.to === "m")),
    };
    const r = semanticEqual(a, b);
    expect(r.diffs.some((d) => d.startsWith("边缺失") && d.includes("seq"))).toBe(true);
  });

  it("选项文本变化：组哈希与边同时变化", () => {
    const a = base();
    const b: BgalsGraph = {
      ...a,
      edges: a.edges.map((e) => (e.text === "去" ? { ...e, text: "走" } : e)),
    };
    const r = semanticEqual(a, b);
    expect(r.equal).toBe(false);
    expect(r.diffs.some((d) => d.includes("节点多出") && d.includes("option_group"))).toBe(true);
    expect(r.diffs.some((d) => d.startsWith("边多出") && d.includes("走"))).toBe(true);
  });

  it("重复内容节点按多重集合计数的确定性", () => {
    const a = base();
    const b: BgalsGraph = {
      ...a,
      nodes: [...a.nodes, dlg("d1", "甲", "你好"), dlg("d2", "甲", "你好")],
    };
    const r = semanticEqual(a, b);
    expect(r.diffs).toContain("节点多出：dialogue 甲：「你好」 ×2");
  });
});
