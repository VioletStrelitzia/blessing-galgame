// BgalsGraph → React Flow 节点/边。option 边给独立 sourceHandle（逐选项行锚点）；
// branch 边共用一个出柄，cond 文案走边标签。

import type { Edge, Node } from "@xyflow/react";
import type { BgalsGraph, GraphNode } from "../../shared/graph";

export interface BranchRow {
  handle: string;
  text?: string;
  cond?: string;
}

export interface FlowData extends Record<string, unknown> {
  node: GraphNode;
  rows: BranchRow[];
}

export type FlowNode = Node<FlowData>;

export function toFlow(graph: BgalsGraph): { nodes: FlowNode[]; edges: Edge[] } {
  const nodes = graph.nodes.map((n) => ({
    id: n.id,
    type: n.kind,
    position: { x: 0, y: 0 },
    data: { node: n, rows: [] as BranchRow[] },
  }));

  const edges: Edge[] = [];
  const branchCount = new Map<string, number>();
  for (const e of graph.edges) {
    const edge: Edge = {
      id: `e${edges.length}`,
      source: e.from,
      target: e.to,
    };
    if (e.kind === "option" || e.kind === "branch") {
      const idx = branchCount.get(e.from) ?? 0;
      branchCount.set(e.from, idx + 1);
      const row: BranchRow = { handle: `r${idx}`, text: e.text, cond: e.cond };
      const node = nodes.find((n) => n.id === e.from);
      node?.data.rows.push(row);
      if (e.kind === "option") edge.sourceHandle = row.handle;
      else edge.label = e.cond ?? "else";
    }
    edges.push(edge);
  }
  return { nodes, edges };
}
