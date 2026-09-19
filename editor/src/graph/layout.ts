// dagre TB 自动布局：按节点形态估算尺寸，布局后回写节点左上角坐标。
// fillMissingPositions 为缺位节点补位：优先挂到已定位前驱下方（级联），孤立节点回退 dagre 全图布局。

import dagre from "@dagrejs/dagre";
import type { Edge } from "@xyflow/react";
import type { BgalsGraph } from "../../shared/graph";
import { toFlow, type FlowNode } from "./toFlow";

export interface Pos {
  x: number;
  y: number;
}

function estimateSize(n: FlowNode): { width: number; height: number } {
  const rows = n.data.rows.length;
  switch (n.data.node.kind) {
    case "start":
    case "end":
      return { width: 96, height: 32 };
    case "dialogue":
      return { width: 280, height: 120 };
    case "inst":
      return { width: 240, height: 76 };
    case "option_group":
      return { width: 240, height: 44 + rows * 26 };
    case "cond":
      return { width: 220, height: 44 + rows * 22 };
    case "jump":
      return { width: 200, height: 52 };
    case "comment":
      return { width: 200, height: 40 };
    case "group":
      return { width: 260, height: 44 + 3 * 22 };
  }
}

export function layoutGraph(nodes: FlowNode[], edges: Edge[]): FlowNode[] {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "TB", nodesep: 36, ranksep: 64, marginx: 24, marginy: 24 });
  g.setDefaultEdgeLabel(() => ({}));
  for (const n of nodes) {
    const s = estimateSize(n);
    g.setNode(n.id, { width: s.width, height: s.height });
  }
  for (const e of edges) g.setEdge(e.source, e.target);
  dagre.layout(g);
  return nodes.map((n) => {
    const s = estimateSize(n);
    const p = g.node(n.id);
    return { ...n, position: { x: p.x - s.width / 2, y: p.y - s.height / 2 } };
  });
}

const DROP_Y = 160;

/**
 * 为 positions 中缺失的节点补位（返回新 Map，入参不动）：
 * 前驱（含 comment 的附着目标）已定位则置于其正下方，循环级联；
 * 仍孤立的节点用 dagre 全图布局兜底（无 sidecar 时即全量 dagre，与 M1 一致）。
 */
export function fillMissingPositions(
  graph: BgalsGraph,
  positions: Map<string, Pos>,
): Map<string, Pos> {
  const out = new Map(positions);
  const preds = new Map<string, string[]>();
  const push = (to: string, from: string) => {
    const l = preds.get(to) ?? [];
    l.push(from);
    preds.set(to, l);
  };
  for (const e of graph.edges) push(e.to, e.from);
  for (const n of graph.nodes) {
    if (n.kind === "comment" && n.before !== null) push(n.id, n.before);
  }

  let progress = true;
  while (progress) {
    progress = false;
    for (const n of graph.nodes) {
      if (out.has(n.id)) continue;
      const placed = (preds.get(n.id) ?? [])
        .map((id) => out.get(id))
        .filter((p): p is Pos => p !== undefined);
      if (placed.length === 0) continue;
      out.set(n.id, {
        x: placed.reduce((s, p) => s + p.x, 0) / placed.length,
        y: Math.max(...placed.map((p) => p.y)) + DROP_Y,
      });
      progress = true;
    }
  }

  if (graph.nodes.some((n) => !out.has(n.id))) {
    const flow = toFlow(graph, out);
    for (const n of layoutGraph(flow.nodes, flow.edges)) {
      if (!out.has(n.id)) out.set(n.id, n.position);
    }
  }
  return out;
}
