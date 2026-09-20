import { describe, expect, it } from "vitest";
import type { BgalsGraph, GraphNode } from "../../shared/graph";
import { toFlow } from "./toFlow";

function makeGraph(nodes: GraphNode[], edges: BgalsGraph["edges"]): BgalsGraph {
  return { format: "bgals-graph/1", compiler: "test", script: "t", nodes, edges };
}

describe("toFlow 孤立 end 过滤", () => {
  it("零入边的 end（jump 终结的剧本）不出现在视图节点中", () => {
    const g = makeGraph(
      [
        { id: "start", kind: "start" },
        { id: "j", kind: "jump", target: "main_menu" },
        { id: "end", kind: "end" },
      ],
      [{ from: "start", to: "j", kind: "seq" }],
    );
    const { nodes } = toFlow(g, new Map());
    expect(nodes.some((n) => n.id === "end")).toBe(false);
    expect(nodes.some((n) => n.id === "j")).toBe(true);
  });

  it("有入边的 end 正常渲染", () => {
    const g = makeGraph(
      [
        { id: "start", kind: "start" },
        { id: "end", kind: "end" },
      ],
      [{ from: "start", to: "end", kind: "seq" }],
    );
    const { nodes } = toFlow(g, new Map());
    expect(nodes.some((n) => n.id === "end")).toBe(true);
  });
});
