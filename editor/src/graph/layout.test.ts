import { describe, expect, it } from "vitest";
import type { BgalsGraph, DialogueNode, GraphEdge } from "../../shared/graph";
import { collapseRuns, groupIdOf, viewPositionsOf } from "./collapse";
import { estimateSizeFor, fillMissingPositions, RANKSEP } from "./layout";

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

/** start → d1..dN（dialogue 链）→ tail（inst，断链）→ end */
function runWithTail(n: number): BgalsGraph {
  const ids = Array.from({ length: n }, (_, i) => `d${i + 1}`);
  const chain = ["start", ...ids, "tail", "end"];
  const edges: GraphEdge[] = chain
    .slice(0, -1)
    .map((id, i) => ({ from: id, to: chain[i + 1], kind: "seq" as const }));
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [
      { id: "start", kind: "start" },
      ...ids.map(dlg),
      { id: "tail", kind: "inst", head: "WAIT", params: { duration: 1 } },
      { id: "end", kind: "end" },
    ],
    edges,
  };
}

describe("视图图布局（fillMissingPositions 作用于聚合后的视图）", () => {
  it("折叠组的出边不再跨空槽：组与后继 y 差 ≤ (组高+后继高)/2 + ranksep 容差", () => {
    const g = runWithTail(7);
    const view = collapseRuns(g, new Set());
    const positions = fillMissingPositions(view, viewPositionsOf(view, new Map()));

    const gid = groupIdOf("d1");
    const gy = positions.get(gid);
    const ty = positions.get("tail");
    expect(gy).toBeDefined();
    expect(ty).toBeDefined();
    const diff = ty!.y - gy!.y;
    // dagre TB：相邻 rank 的左上角 y 差 = 上层节点高 + ranksep
    const allowed = estimateSizeFor("group").height + RANKSEP + 1;
    expect(diff).toBeGreaterThan(0);
    expect(diff).toBeLessThanOrEqual(allowed);

    // 对照：领域图（未折叠）布局下 tail 在 7 个成员槽位之后，远超该容差
    const domain = fillMissingPositions(g, new Map());
    const domainDiff = domain.get("tail")!.y - domain.get("d1")!.y;
    expect(domainDiff).toBeGreaterThan(allowed);
  });

  it("级联补位走视图边：组的后继缺位时挂在组下方", () => {
    const g = runWithTail(5);
    const view = collapseRuns(g, new Set());
    const seed = viewPositionsOf(view, new Map());
    // 只给组一个位置，tail 走级联（组的出边是视图边）
    seed.set(groupIdOf("d1"), { x: 100, y: 100 });
    const positions = fillMissingPositions(view, seed);
    expect(positions.get("tail")!.y).toBeGreaterThan(100);
  });
});
