import { describe, expect, it } from "vitest";
import type { BgalsGraph, DialogueNode, GraphEdge } from "../../shared/graph";
import { findRuns, groupIdOf, stackPositions } from "./collapse";
import { FRAME_PAD_TOP, FRAME_PAD_X, frameRects } from "./frames";
import { estimateSizeFor } from "./layout";

function dlg(id: string): DialogueNode {
  return {
    id,
    kind: "dialogue",
    character: "",
    text: id,
    display_text: id,
    anchors: [],
    prev: [],
    post: [],
  };
}

/** start → d1..dN → end */
function dialogueRun(n: number): BgalsGraph {
  const ids = Array.from({ length: n }, (_, i) => `d${i + 1}`);
  const chain = ["start", ...ids, "end"];
  const edges: GraphEdge[] = chain
    .slice(0, -1)
    .map((id, i) => ({ from: id, to: chain[i + 1], kind: "seq" as const }));
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [{ id: "start", kind: "start" }, ...ids.map(dlg), { id: "end", kind: "end" }],
    edges,
  };
}

describe("frameRects（展开链的分组边界框）", () => {
  it("展开链生成包围盒：覆盖全部成员（含 padding）", () => {
    const g = dialogueRun(6);
    const gid = groupIdOf("d1");
    const runs = findRuns(g, new Set());
    const base = { x: 100, y: 200 };
    const positions = new Map(stackPositions(base, 6).map((p, i) => [`d${i + 1}`, p] as const));
    const rects = frameRects(runs, new Set([gid]), positions);
    expect(rects).toHaveLength(1);
    const r = rects[0];
    expect(r.groupId).toBe(gid);
    expect(r.label).toBe("DIALOGUE ×6");
    // 每个成员的估算包围盒都落在 frame 内
    const size = estimateSizeFor("dialogue");
    for (let i = 0; i < 6; i++) {
      const p = positions.get(`d${i + 1}`)!;
      expect(p.x).toBeGreaterThanOrEqual(r.x + FRAME_PAD_X - 1);
      expect(p.y).toBeGreaterThanOrEqual(r.y + FRAME_PAD_TOP - 1);
      expect(p.x + size.width).toBeLessThanOrEqual(r.x + r.width - FRAME_PAD_X + 1);
      expect(p.y + size.height).toBeLessThanOrEqual(r.y + r.height);
    }
  });

  it("未展开（折叠中）的链不生成 frame", () => {
    const g = dialogueRun(6);
    const rects = frameRects(findRuns(g, new Set()), new Set(), new Map());
    expect(rects).toHaveLength(0);
  });

  it("成员位置全缺时跳过（不产生无穷矩形）", () => {
    const g = dialogueRun(6);
    const rects = frameRects(findRuns(g, new Set()), new Set([groupIdOf("d1")]), new Map());
    expect(rects).toHaveLength(0);
  });
});
