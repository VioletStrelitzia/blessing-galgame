// bgals-overview/1 → React Flow 节点/边（总览视图，纯函数；布局 dagre LR，每次载入重算）。
// 剧本节点青色、begin 剧本绿描边 + BEGIN 标签、main_menu 灰色终态胶囊、missing 目标玫瑰色虚线幽灵。

import dagre from "@dagrejs/dagre";
import type { Edge, Node } from "@xyflow/react";
import { MAIN_MENU, type BgalsOverview, type OverviewScript } from "../../shared/overview";

export interface OverviewNodeData extends Record<string, unknown> {
  label: string;
  stats?: OverviewScript;
  begin?: boolean;
  /** main_menu 终态 */
  terminal?: boolean;
  /** jump 了但不存在的目标 */
  ghost?: boolean;
}

export type OverviewFlowNode = Node<OverviewNodeData>;

/** 统计行：`13 对话 · 6 指令 · 1 选项 · 1 分支 · 2 跳转`（零值省略） */
export function statsLine(s: OverviewScript): string {
  const parts: string[] = [];
  if (s.dialogues > 0) parts.push(`${s.dialogues} 对话`);
  if (s.insts > 0) parts.push(`${s.insts} 指令`);
  if (s.options > 0) parts.push(`${s.options} 选项`);
  if (s.conds > 0) parts.push(`${s.conds} 分支`);
  if (s.jumps > 0) parts.push(`${s.jumps} 跳转`);
  return parts.length > 0 ? parts.join(" · ") : "空剧本";
}

function estimateSize(n: OverviewFlowNode): { width: number; height: number } {
  if (n.data.terminal) return { width: 140, height: 40 };
  if (n.data.ghost) return { width: 180, height: 48 };
  return { width: 220, height: 64 };
}

export function buildOverviewFlow(overview: BgalsOverview): {
  nodes: OverviewFlowNode[];
  edges: Edge[];
} {
  const nodes: OverviewFlowNode[] = overview.scripts.map((s) => ({
    id: s.name,
    type: "script",
    position: { x: 0, y: 0 },
    data: { label: s.name, stats: s, begin: s.name === overview.begin },
  }));
  if (overview.edges.some((e) => e.to === MAIN_MENU)) {
    nodes.push({
      id: MAIN_MENU,
      type: "terminal",
      position: { x: 0, y: 0 },
      data: { label: MAIN_MENU, terminal: true },
    });
  }
  for (const name of overview.missing) {
    nodes.push({
      id: name,
      type: "ghost",
      position: { x: 0, y: 0 },
      data: { label: name, ghost: true },
    });
  }

  const edges: Edge[] = overview.edges.map((e, i) => ({
    id: `o${i}`,
    source: e.from,
    target: e.to,
  }));
  // 防御：边端点必须在节点集中（missing 已在上方建幽灵节点）
  const ids = new Set(nodes.map((n) => n.id));
  const safeEdges = edges.filter((e) => ids.has(e.source) && ids.has(e.target));

  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", nodesep: 40, ranksep: 120, marginx: 24, marginy: 24 });
  g.setDefaultEdgeLabel(() => ({}));
  for (const n of nodes) {
    const s = estimateSize(n);
    g.setNode(n.id, { width: s.width, height: s.height });
  }
  for (const e of safeEdges) g.setEdge(e.source, e.target);
  dagre.layout(g);
  const laid = nodes.map((n) => {
    const s = estimateSize(n);
    const p = g.node(n.id);
    return { ...n, position: { x: p.x - s.width / 2, y: p.y - s.height / 2 } };
  });
  return { nodes: laid, edges: safeEdges };
}
