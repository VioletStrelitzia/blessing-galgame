import { describe, expect, it } from "vitest";
import type { BgalsGraph, DialogueNode, GraphEdge, GraphNode, InstNode } from "../../shared/graph";
import {
  COLLAPSE_THRESHOLD,
  EXPAND_GAP_Y,
  collapseRuns,
  groupIdOf,
  isGroupNode,
  stackPositions,
} from "./collapse";

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
function inst(id: string, head = "WAIT"): InstNode {
  return { id, kind: "inst", head, params: {} };
}
function seqChain(ids: string[]): GraphEdge[] {
  return ids.slice(0, -1).map((id, i) => ({ from: id, to: ids[i + 1], kind: "seq" as const }));
}
function makeGraph(nodes: GraphNode[], edges: GraphEdge[]): BgalsGraph {
  return { format: "bgals-graph/1", compiler: "test", script: "t", nodes, edges };
}

/** start → d1..dN → end 的对话长链 */
function dialogueRun(n: number): BgalsGraph {
  const ids = Array.from({ length: n }, (_, i) => `d${i + 1}`);
  return makeGraph(
    [{ id: "start", kind: "start" }, ...ids.map(dlg), { id: "end", kind: "end" }],
    seqChain(["start", ...ids, "end"]),
  );
}

describe("collapseRuns", () => {
  it(`链长 < ${COLLAPSE_THRESHOLD} 不折叠，≥ ${COLLAPSE_THRESHOLD} 折叠`, () => {
    const under = dialogueRun(COLLAPSE_THRESHOLD - 1);
    const v = collapseRuns(under, new Set());
    expect(v.nodes).toHaveLength(under.nodes.length);
    expect(v.nodes.some(isGroupNode)).toBe(false);
    // 恰为阈值即折叠
    const at = dialogueRun(COLLAPSE_THRESHOLD);
    const v2 = collapseRuns(at, new Set());
    expect(v2.nodes.filter(isGroupNode)).toHaveLength(1);
  });

  it("长链折叠为 group 节点：摘要首 2 尾 1、hiddenCount、边重连", () => {
    const g = dialogueRun(7);
    const v = collapseRuns(g, new Set());
    const group = v.nodes.find(isGroupNode);
    expect(group).toBeDefined();
    expect(group!.id).toBe(groupIdOf("d1"));
    expect(group!.groupKind).toBe("dialogue");
    expect(group!.runIds).toHaveLength(7);
    expect(group!.summary.map((n) => n.id)).toEqual(["d1", "d2", "d7"]);
    expect(group!.hiddenCount).toBe(4);
    // start → group → end
    expect(v.edges).toHaveLength(2);
    expect(v.edges[0]).toMatchObject({ from: "start", to: group!.id });
    expect(v.edges[1]).toMatchObject({ from: group!.id, to: "end" });
    expect(v.nodes).toHaveLength(3);
  });

  it("expanded 集合中的链不折叠", () => {
    const g = dialogueRun(6);
    const v = collapseRuns(g, new Set([groupIdOf("d1")]));
    expect(v.nodes.some(isGroupNode)).toBe(false);
    expect(v.nodes).toHaveLength(g.nodes.length);
  });

  it("kind 不一致的链不折叠（dialogue 与 inst 交替）", () => {
    const nodes: GraphNode[] = [{ id: "start", kind: "start" }];
    const ids: string[] = [];
    for (let i = 0; i < 8; i++) {
      const id = `n${i}`;
      ids.push(id);
      nodes.push(i % 2 === 0 ? dlg(id) : inst(id));
    }
    nodes.push({ id: "end", kind: "end" });
    const v = collapseRuns(makeGraph(nodes, seqChain(["start", ...ids, "end"])), new Set());
    expect(v.nodes.some(isGroupNode)).toBe(false);
  });

  it("强制可见节点把链拆短（带诊断/选中不参与折叠）", () => {
    const g = dialogueRun(11); // d1..d11；强制 d6 可见 → d1-d5 折叠 + d6 + d7-d11 折叠
    const v = collapseRuns(g, new Set(), new Set(["d6"]));
    const groups = v.nodes.filter(isGroupNode);
    expect(groups.map((g2) => g2.runIds)).toEqual([
      ["d1", "d2", "d3", "d4", "d5"],
      ["d7", "d8", "d9", "d10", "d11"],
    ]);
    expect(v.nodes.some((n) => n.id === "d6")).toBe(true);
    // d6 的入边来自前组、出边指向后组
    expect(v.edges.some((e) => e.from === groups[0].id && e.to === "d6")).toBe(true);
    expect(v.edges.some((e) => e.from === "d6" && e.to === groups[1].id)).toBe(true);
  });

  it("option 合流点断开链（多入边不折叠）", () => {
    const ids = ["a1", "a2", "a3", "a4", "a5", "a6"];
    const edges = seqChain(["start", ...ids, "end"]);
    edges.push({ from: "start", to: "a4", kind: "option", text: " shortcut" }); // a4 多一条入边
    const v = collapseRuns(
      makeGraph(
        [{ id: "start", kind: "start" }, ...ids.map(dlg), { id: "end", kind: "end" }],
        edges,
      ),
      new Set(),
    );
    // a1-a3 长度 3 不折；a4-a6 长度 3 不折
    expect(v.nodes.some(isGroupNode)).toBe(false);
  });

  it("inst 长链同样折叠，groupKind 为 inst", () => {
    const ids = ["m1", "m2", "m3", "m4", "m5"];
    const g = makeGraph(
      [{ id: "start", kind: "start" }, ...ids.map((i) => inst(i)), { id: "end", kind: "end" }],
      seqChain(["start", ...ids, "end"]),
    );
    const v = collapseRuns(g, new Set());
    const group = v.nodes.find(isGroupNode);
    expect(group?.groupKind).toBe("inst");
  });
});

describe("stackPositions（展开聚合链的位置分配）", () => {
  it("从基准位置垂直堆叠：x 对齐，按成员高度 + 净距累加", () => {
    expect(stackPositions({ x: 100, y: 200 }, [100, 60, 80])).toEqual([
      { x: 100, y: 200 },
      { x: 100, y: 200 + 100 + EXPAND_GAP_Y },
      { x: 100, y: 200 + 100 + 60 + EXPAND_GAP_Y * 2 },
    ]);
  });

  it("自定义净距与空链", () => {
    expect(stackPositions({ x: 0, y: 0 }, [50, 50], 10)).toEqual([
      { x: 0, y: 0 },
      { x: 0, y: 60 },
    ]);
    expect(stackPositions({ x: 1, y: 2 }, [])).toEqual([]);
  });
});
