import { describe, expect, it } from "vitest";
import type { BgalsGraph, GraphEdge, GraphNode } from "./graph";
import { flowNeighbor } from "./graph_walk";

function makeGraph(nodes: GraphNode[], edges: GraphEdge[]): BgalsGraph {
  return { format: "bgals-graph/1", compiler: "test", script: "t", nodes, edges };
}

/** start → a → b → end */
function linear(): BgalsGraph {
  const d = (id: string): GraphNode => ({
    id,
    kind: "dialogue",
    character: "",
    text: id,
    display_text: id,
    anchors: [],
    prev: [],
    post: [],
  });
  return makeGraph(
    [{ id: "start", kind: "start" }, d("a"), d("b"), { id: "end", kind: "end" }],
    [
      { from: "start", to: "a", kind: "seq" },
      { from: "a", to: "b", kind: "seq" },
      { from: "b", to: "end", kind: "seq" },
    ],
  );
}

/** start → g(选项组: x→b1, y→b2) → b1/b2 → m → end */
function optioned(): BgalsGraph {
  const d = (id: string): GraphNode => ({
    id,
    kind: "dialogue",
    character: "",
    text: id,
    display_text: id,
    anchors: [],
    prev: [],
    post: [],
  });
  return makeGraph(
    [
      { id: "start", kind: "start" },
      { id: "g", kind: "option_group" },
      d("b1"),
      d("b2"),
      d("m"),
      { id: "end", kind: "end" },
    ],
    [
      { from: "start", to: "g", kind: "seq" },
      { from: "g", to: "b1", kind: "option", text: "x" },
      { from: "g", to: "b2", kind: "option", text: "y" },
      { from: "b1", to: "m", kind: "seq" },
      { from: "b2", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ],
  );
}

describe("flowNeighbor", () => {
  it("线性链：next=seq 后继，prev=seq 前驱；start 无上、end 无下", () => {
    const g = linear();
    expect(flowNeighbor(g, "a", 1)).toBe("b");
    expect(flowNeighbor(g, "b", -1)).toBe("a");
    expect(flowNeighbor(g, "start", -1)).toBeNull();
    expect(flowNeighbor(g, "end", 1)).toBeNull();
    expect(flowNeighbor(g, "start", 1)).toBe("a");
    expect(flowNeighbor(g, "b", 1)).toBe("end");
  });

  it("选项组：next 取汇合点；分支头 prev 取组；汇合点 prev 取首个 seq 前驱", () => {
    const g = optioned();
    expect(flowNeighbor(g, "g", 1)).toBe("m");
    expect(flowNeighbor(g, "b1", -1)).toBe("g");
    expect(flowNeighbor(g, "b2", -1)).toBe("g");
    expect(flowNeighbor(g, "m", -1)).toBe("b1"); // seq 优先，数组序首个
    expect(flowNeighbor(g, "m", 1)).toBe("end");
  });

  it("jump 无下一个；jump 的 prev 正常", () => {
    const g = linear();
    g.nodes.push({ id: "j", kind: "jump", target: "main_menu" });
    g.edges.push({ from: "b", to: "j", kind: "seq" });
    expect(flowNeighbor(g, "j", 1)).toBeNull();
    expect(flowNeighbor(g, "j", -1)).toBe("b");
  });

  it("无汇合点的条件链 next 为 null；未知节点/comment 为 null", () => {
    const g = linear();
    g.nodes.push({ id: "c", kind: "cond" });
    g.edges.push({ from: "b", to: "c", kind: "seq" });
    g.edges.push({ from: "c", to: "end", kind: "branch", cond: "true" });
    // c 只有一条分支且直指 end：汇合点 = end
    expect(flowNeighbor(g, "c", 1)).toBe("end");
    expect(flowNeighbor(g, "nobody", 1)).toBeNull();
    g.nodes.push({ id: "cm", kind: "comment", text: "", before: null });
    expect(flowNeighbor(g, "cm", 1)).toBeNull();
    expect(flowNeighbor(g, "cm", -1)).toBeNull();
  });
});
