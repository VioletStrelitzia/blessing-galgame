// BgalsGraph → React Flow 节点/边。option 边给独立 sourceHandle（逐选项行锚点）；
// branch 边共用一个出柄，cond 文案走边标签。comment 节点不参与连线，渲染为游离便签。
// 位置来自 store 的 positions（sidecar + dagre 补位），React Flow 仅为视图投影。

import type { Edge, Node } from "@xyflow/react";
import type { BgalsGraph, GraphNode } from "../../shared/graph";

export interface BranchRow {
  handle: string;
  text?: string;
  cond?: string;
}

/** 节点角标：映射到该节点的诊断计数 */
export interface DiagBadge {
  error: number;
  warning: number;
}

export interface FlowData extends Record<string, unknown> {
  node: GraphNode;
  rows: BranchRow[];
  diags?: DiagBadge;
}

export type FlowNode = Node<FlowData>;

export interface FlowEdgeData extends Record<string, unknown> {
  /** 对应 BgalsGraph.edges 的数组下标（insertOnEdge 等操作的入参） */
  edgeIndex: number;
  kind: string;
}

export function toFlow(
  graph: BgalsGraph,
  positions: Map<string, { x: number; y: number }>,
  nodeDiags: Record<string, DiagBadge> = {},
): { nodes: FlowNode[]; edges: Edge[] } {
  const nodes = graph.nodes.map((n) => ({
    id: n.id,
    type: n.kind,
    position: positions.get(n.id) ?? { x: 0, y: 0 },
    data: { node: n, rows: [] as BranchRow[], diags: nodeDiags[n.id] },
  }));

  const edges: Edge[] = [];
  const branchCount = new Map<string, number>();
  graph.edges.forEach((e, i) => {
    const edge: Edge = {
      id: `e${i}`,
      source: e.from,
      target: e.to,
      data: { edgeIndex: i, kind: e.kind } satisfies FlowEdgeData,
    };
    if (e.kind === "seq") edge.type = "seq";
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
  });
  return { nodes, edges };
}
