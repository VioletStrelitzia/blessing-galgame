// 连续同类节点聚合（纯视图层，不动领域图）：成串 dialogue/inst 折叠为 group 视图节点。
// 极大纯 seq 链：链内 kind 全同（dialogue 或 inst）、彼此仅一条 seq 边相连（成员唯一入边）、
// 无 option/branch/jump 混入；链长 > COLLAPSE_THRESHOLD 才折叠。带诊断/当前选中节点强制可见。

import type { BgalsGraph, GraphEdge, GraphNode } from "../../shared/graph";

/** 链长超过该值才折叠 */
export const COLLAPSE_THRESHOLD = 4;

export interface GroupViewNode {
  id: string; // group:<首节点 id>
  kind: "group";
  groupKind: "dialogue" | "inst";
  /** 链内全部真实节点 id（顺序） */
  runIds: string[];
  /** 摘要：首 2 条 + 尾 1 条真实节点 */
  summary: GraphNode[];
  hiddenCount: number;
}

export type ViewNode = GraphNode | GroupViewNode;

export interface ViewGraph {
  nodes: ViewNode[];
  edges: GraphEdge[];
}

export function isGroupNode(n: ViewNode): n is GroupViewNode {
  return n.kind === "group";
}

export function groupIdOf(firstId: string): string {
  return `group:${firstId}`;
}

export function collapseRuns(
  graph: BgalsGraph,
  expanded: Set<string>,
  forcedVisible: Set<string> = new Set(),
): ViewGraph {
  const byId = new Map(graph.nodes.map((n) => [n.id, n]));
  const seqOut = new Map<string, number>();
  const incoming = new Map<string, number[]>();
  graph.edges.forEach((e, i) => {
    if (e.kind === "seq" && !seqOut.has(e.from)) seqOut.set(e.from, i);
    const l = incoming.get(e.to) ?? [];
    l.push(i);
    incoming.set(e.to, l);
  });

  const eligible = (id: string): GraphNode | undefined => {
    const n = byId.get(id);
    if (!n || (n.kind !== "dialogue" && n.kind !== "inst")) return undefined;
    if (forcedVisible.has(id)) return undefined;
    return n;
  };
  /** 唯一入边且为 seq 时才可续链（option/branch 合流点断开） */
  const solePredOf = (id: string): GraphNode | undefined => {
    const inc = incoming.get(id) ?? [];
    if (inc.length !== 1) return undefined;
    const e = graph.edges[inc[0]];
    if (e.kind !== "seq") return undefined;
    return eligible(e.from);
  };

  const runByHead = new Map<string, GraphNode[]>();
  const inRun = new Set<string>();
  for (const n of graph.nodes) {
    const head = eligible(n.id);
    if (!head || inRun.has(n.id)) continue;
    const pred = solePredOf(n.id);
    if (pred !== undefined && pred.kind === head.kind) continue; // 非链头
    const run: GraphNode[] = [head];
    inRun.add(head.id);
    for (;;) {
      const cur = run[run.length - 1];
      const si = seqOut.get(cur.id);
      if (si === undefined) break;
      const nxtId = graph.edges[si].to;
      const nxt = eligible(nxtId);
      if (!nxt || nxt.kind !== head.kind || inRun.has(nxtId)) break;
      if (solePredOf(nxtId)?.id !== cur.id) break;
      run.push(nxt);
      inRun.add(nxtId);
    }
    if (run.length > COLLAPSE_THRESHOLD && !expanded.has(groupIdOf(run[0].id))) {
      runByHead.set(run[0].id, run);
    }
  }
  if (runByHead.size === 0) return { nodes: graph.nodes, edges: graph.edges };

  const memberToGroup = new Map<string, string>();
  for (const [headId, run] of runByHead) {
    for (const n of run) memberToGroup.set(n.id, groupIdOf(headId));
  }

  const nodes: ViewNode[] = [];
  for (const n of graph.nodes) {
    const run = runByHead.get(n.id);
    if (run) {
      nodes.push({
        id: groupIdOf(n.id),
        kind: "group",
        groupKind: n.kind as "dialogue" | "inst",
        runIds: run.map((r) => r.id),
        summary: [run[0], run[1], run[run.length - 1]],
        hiddenCount: run.length - 3,
      });
    } else if (!memberToGroup.has(n.id)) {
      nodes.push(n);
    }
  }

  const edges: GraphEdge[] = [];
  for (const e of graph.edges) {
    const from = memberToGroup.get(e.from);
    const to = memberToGroup.get(e.to);
    if (from !== undefined && from === to) continue; // 组内 seq 边 → 自环，丢弃
    if (from !== undefined || to !== undefined) {
      edges.push({ ...e, from: from ?? e.from, to: to ?? e.to });
    } else {
      edges.push(e);
    }
  }
  return { nodes, edges };
}
