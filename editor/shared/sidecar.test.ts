import { describe, expect, it } from "vitest";
import type { BgalsGraph, DialogueNode } from "./graph";
import { applySidecar, buildSidecar, contentHash, type Sidecar } from "./sidecar";

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

/** start → a → b → end（a、b 为同名同文对话，用于撞哈希） */
function twinGraph(): BgalsGraph {
  return {
    format: "bgals-graph/1",
    compiler: "bgals2.4",
    script: "t",
    nodes: [
      { id: "start", kind: "start" },
      dlg("a", "甲", "同文"),
      dlg("b", "甲", "同文"),
      { id: "end", kind: "end" },
    ],
    edges: [
      { from: "start", to: "a", kind: "seq" },
      { from: "a", to: "b", kind: "seq" },
      { from: "b", to: "end", kind: "seq" },
    ],
  };
}

describe("contentHash", () => {
  it("稳定且不含 id；语义字段变化即变", () => {
    expect(contentHash(dlg("x", "甲", "同文"))).toBe(contentHash(dlg("y", "甲", "同文")));
    expect(contentHash(dlg("x", "甲", "同文"))).not.toBe(contentHash(dlg("x", "乙", "同文")));
    expect(contentHash(dlg("x", "甲", "同文"))).not.toBe(contentHash(dlg("x", "甲", "异文")));
  });

  it("params 排序键（键序无关）；prev/post 参与哈希", () => {
    const h1 = contentHash({ id: "i", kind: "inst", head: "WAIT", params: { a: 1, b: 2 } });
    const h2 = contentHash({ id: "j", kind: "inst", head: "WAIT", params: { b: 2, a: 1 } });
    expect(h1).toBe(h2);
    const d1 = dlg("d", "", "t");
    d1.prev = [{ kind: "inst", head: "WAIT", params: { duration: 1 } }];
    expect(contentHash(d1)).not.toBe(contentHash(dlg("d", "", "t")));
  });

  it("option_group/cond 哈希含分支 text+cond 列表", () => {
    const g = { id: "g", kind: "option_group" } as const;
    const h1 = contentHash(g, [{ from: "g", to: "x", kind: "option", text: "甲" }]);
    const h2 = contentHash(g, [{ from: "g", to: "x", kind: "option", text: "乙" }]);
    expect(h1).not.toBe(h2);
    const c = { id: "c", kind: "cond" } as const;
    const h3 = contentHash(c, [
      { from: "c", to: "x", kind: "branch", cond: "a" },
      { from: "c", to: "y", kind: "branch" },
    ]);
    const h4 = contentHash(c, [{ from: "c", to: "x", kind: "branch", cond: "a" }]);
    expect(h3).not.toBe(h4);
  });
});

describe("buildSidecar / applySidecar", () => {
  it("往返：布局与注释经哈希匹配还原", () => {
    let g = twinGraph();
    g = {
      ...g,
      nodes: [
        ...g.nodes.slice(0, 3),
        dlg("u", "乙", "独特"),
        ...g.nodes.slice(3),
        { id: "c1", kind: "comment", text: "头注", before: null },
        { id: "c2", kind: "comment", text: "附着独特节点", before: "u" },
        { id: "c3", kind: "comment", text: "附着第二个同文", before: "b" },
      ],
      edges: [
        { from: "start", to: "a", kind: "seq" },
        { from: "a", to: "b", kind: "seq" },
        { from: "b", to: "u", kind: "seq" },
        { from: "u", to: "end", kind: "seq" },
      ],
    };
    const positions = new Map([
      ["start", { x: 0, y: 0 }],
      ["a", { x: 0, y: 100 }],
      ["b", { x: 0, y: 200 }],
      ["u", { x: 0, y: 300 }],
      ["end", { x: 0, y: 400 }],
      ["c1", { x: 300, y: 0 }],
      ["c2", { x: 300, y: 280 }],
      ["c3", { x: 300, y: 180 }],
    ]);
    const sidecar = buildSidecar(g, positions);
    expect(sidecar.format).toBe("bgals-editor/1");
    expect(sidecar.compiler).toBe("bgals2.4");
    expect(sidecar.comments).toHaveLength(3);

    // 模拟 id 漂移后的新图（同内容，全新 id，顺序一致）
    const g2: BgalsGraph = {
      ...g,
      nodes: [
        { id: "s", kind: "start" },
        dlg("n1", "甲", "同文"),
        dlg("n2", "甲", "同文"),
        dlg("n3", "乙", "独特"),
        { id: "e", kind: "end" },
      ],
      edges: [
        { from: "s", to: "n1", kind: "seq" },
        { from: "n1", to: "n2", kind: "seq" },
        { from: "n2", to: "n3", kind: "seq" },
        { from: "n3", to: "e", kind: "seq" },
      ],
    };
    const { positions: p2, comments } = applySidecar(g2, sidecar);
    expect(p2.get("n1")).toEqual({ x: 0, y: 100 });
    expect(p2.get("n2")).toEqual({ x: 0, y: 200 });
    expect(p2.get("n3")).toEqual({ x: 0, y: 300 });
    expect(comments).toHaveLength(3);
    expect(comments[0]).toMatchObject({ id: "c1", text: "头注", before: null });
    // 唯一哈希精确还原
    expect(comments[1]).toMatchObject({ id: "c2", before: "n3" });
    // 同名同文节点哈希不可区分：按出现顺序确定性兜底（可能漂移，但不随机）
    expect(comments[2]).toMatchObject({ id: "c3", before: "n1" });
  });

  it("漂移：哈希匹配不到的布局项跳过；beforeHash 匹配不到降级 null", () => {
    const g = twinGraph();
    const sidecar: Sidecar = {
      format: "bgals-editor/1",
      compiler: "bgals2.4",
      script: "t",
      layout: [
        { hash: "deadbeef", x: 1, y: 1 },
        { hash: contentHash(dlg("z", "甲", "同文")), x: 5, y: 5 },
        { hash: contentHash(dlg("z", "甲", "同文")), x: 6, y: 6 },
        { hash: contentHash(dlg("z", "甲", "同文")), x: 7, y: 7 }, // 第三个无配对
      ],
      comments: [{ id: "c", text: "注", beforeHash: "deadbeef" }],
    };
    const { positions, comments } = applySidecar(g, sidecar);
    expect(positions.get("a")).toEqual({ x: 5, y: 5 });
    expect(positions.get("b")).toEqual({ x: 6, y: 6 });
    expect(positions.size).toBe(2);
    expect(comments[0]).toMatchObject({ before: null });
  });

  it("格式版本不符抛错", () => {
    const bad = { format: "bgals-editor/0", compiler: "", script: "", layout: [], comments: [] };
    expect(() => applySidecar(twinGraph(), bad as Sidecar)).toThrow("未知 sidecar 格式");
  });
});
