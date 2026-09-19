// ViewGraph（领域图经 collapseRuns 聚合后的视图）→ React Flow 节点/边。
// option 边给独立 sourceHandle（逐选项行锚点）；branch 边共用一个出柄，cond 文案走边标签。
// comment 节点不参与连线，渲染为游离便签；group 为聚合视图节点（不可选不可拖）。
// 位置来自 store 的 positions（sidecar + dagre 补位），React Flow 仅为视图投影。

import type { Edge, Node } from "@xyflow/react";
import type { GraphEdge } from "../../shared/graph";
import { isGroupNode, type ViewGraph, type ViewNode } from "./collapse";

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
  node: ViewNode;
  rows: BranchRow[];
  diags?: DiagBadge;
  /** 展开中的聚合链首节点 id（group:<id>），NodeShell 据此渲染「收起」按钮 */
  collapseId?: string;
}

export type FlowNode = Node<FlowData>;

export interface FlowEdgeData extends Record<string, unknown> {
  /** 对应领域图 BgalsGraph.edges 的数组下标（insertOnEdge 等操作的入参）；-1 = 视图合成边 */
  edgeIndex: number;
  kind: string;
  /** 触及 group 节点或为聚合产物：不显示「+」插入按钮 */
  synthetic: boolean;
}

export function toFlow(
  graph: ViewGraph,
  positions: Map<string, { x: number; y: number }>,
  nodeDiags: Record<string, DiagBadge> = {},
  /** 领域图 edges（用于把视图边映射回领域下标）；缺省即视图边本身（布局兜底用） */
  domainEdges: GraphEdge[] = graph.edges,
): { nodes: FlowNode[]; edges: Edge[] } {
  const groupIds = new Set(graph.nodes.filter(isGroupNode).map((n) => n.id));
  const nodes = graph.nodes.map((n) => ({
    id: n.id,
    type: n.kind,
    position:
      positions.get(n.id) ??
      (isGroupNode(n) ? positions.get(n.runIds[0]) : undefined) ??
      ({ x: 0, y: 0 } as const),
    selectable: !isGroupNode(n),
    draggable: true, // 组节点可拖（位置以 group:xxx 键写入，读取侧兼容）
    data: { node: n, rows: [] as BranchRow[], diags: nodeDiags[n.id] },
  }));

  const edges: Edge[] = [];
  const branchCount = new Map<string, number>();
  graph.edges.forEach((e, i) => {
    const domainIndex = domainEdges.indexOf(e);
    const edge: Edge = {
      id: `e${i}`,
      source: e.from,
      target: e.to,
      data: {
        edgeIndex: domainIndex,
        kind: e.kind,
        synthetic: domainIndex < 0 || groupIds.has(e.from) || groupIds.has(e.to),
      } satisfies FlowEdgeData,
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
