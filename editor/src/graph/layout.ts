// dagre TB 自动布局：按节点形态估算尺寸，布局后回写节点左上角坐标。

import dagre from "@dagrejs/dagre";
import type { Edge } from "@xyflow/react";
import type { FlowNode } from "./toFlow";

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
