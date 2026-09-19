// 图导航与公共小工具：flowIndex 邻接索引、可达性、汇合点判定、孤悬清扫。
// 汇合点口径与 emit.ts 一致：各分支共同可达、距组头最近（BFS）。

import type { BgalsGraph, GraphNode } from "./graph";

export interface FlowIndex {
  nodes: Map<string, GraphNode>;
  /** 首条 seq 出边的 edges 下标 */
  seqOut: Map<string, number>;
  /** option/branch 出边下标（edges 数组序 = 分支序） */
  branchOut: Map<string, number[]>;
  /** 全部入边下标 */
  incoming: Map<string, number[]>;
  startId?: string;
  endId?: string;
}

export function flowIndex(graph: BgalsGraph): FlowIndex {
  const idx: FlowIndex = {
    nodes: new Map(),
    seqOut: new Map(),
    branchOut: new Map(),
    incoming: new Map(),
  };
  for (const n of graph.nodes) {
    idx.nodes.set(n.id, n);
    if (n.kind === "start") idx.startId = n.id;
    if (n.kind === "end") idx.endId = n.id;
  }
  graph.edges.forEach((e, i) => {
    if (e.kind === "seq") {
      if (!idx.seqOut.has(e.from)) idx.seqOut.set(e.from, i);
    } else if (e.kind === "option" || e.kind === "branch") {
      const list = idx.branchOut.get(e.from) ?? [];
      list.push(i);
      idx.branchOut.set(e.from, list);
    }
    const inc = idx.incoming.get(e.to) ?? [];
    inc.push(i);
    idx.incoming.set(e.to, inc);
  });
  return idx;
}

function adjacency(idx: FlowIndex, graph: BgalsGraph, id: string): string[] {
  const nexts: string[] = [];
  const s = idx.seqOut.get(id);
  if (s !== undefined) nexts.push(graph.edges[s].to);
  for (const b of idx.branchOut.get(id) ?? []) nexts.push(graph.edges[b].to);
  return nexts;
}

/** 经 seq/option/branch 边可达的节点集合（含起点） */
export function reachableFrom(graph: BgalsGraph, from: string[]): Set<string> {
  const idx = flowIndex(graph);
  const seen = new Set<string>();
  const stack = [...from];
  while (stack.length > 0) {
    const id = stack.pop()!;
    if (seen.has(id) || !idx.nodes.has(id)) continue;
    seen.add(id);
    stack.push(...adjacency(idx, graph, id));
  }
  return seen;
}

/** 组/条件节点的汇合点：各分支共同可达、BFS 距组头最近；无（如分支全以 jump 终结）返回 undefined */
export function findMerge(graph: BgalsGraph, groupId: string): string | undefined {
  const idx = flowIndex(graph);
  const targets = (idx.branchOut.get(groupId) ?? []).map((i) => graph.edges[i].to);
  if (targets.length === 0) return undefined;
  let common = reachableFrom(graph, [targets[0]]);
  for (const t of targets.slice(1)) {
    const r = reachableFrom(graph, [t]);
    common = new Set([...common].filter((id) => r.has(id)));
  }
  if (common.size === 0) return undefined;
  const queue = [groupId];
  const seen = new Set<string>([groupId]);
  while (queue.length > 0) {
    const id = queue.shift()!;
    for (const n of adjacency(idx, graph, id)) {
      if (seen.has(n)) continue;
      if (common.has(n)) return n;
      seen.add(n);
      queue.push(n);
    }
  }
  return undefined;
}

/** 节点的流程后继：普通节点取 seq 出边目标；option_group/cond 取汇合点 */
export function successorOf(graph: BgalsGraph, id: string): string | undefined {
  const idx = flowIndex(graph);
  const seq = idx.seqOut.get(id);
  if (seq !== undefined) return graph.edges[seq].to;
  const node = idx.nodes.get(id);
  if (node?.kind === "option_group" || node?.kind === "cond") return findMerge(graph, id);
  return undefined;
}

/**
 * 孤悬清扫：删除 start 不可达的非 comment 节点（end 始终保留）及相关边；
 * comment 的 before 指向被删节点时降级为 null（文件头）。
 */
export function sweepOrphans(graph: BgalsGraph): BgalsGraph {
  const idx = flowIndex(graph);
  const keep = idx.startId ? reachableFrom(graph, [idx.startId]) : new Set<string>();
  if (idx.endId) keep.add(idx.endId);
  const removed = new Set(
    graph.nodes.filter((n) => n.kind !== "comment" && !keep.has(n.id)).map((n) => n.id),
  );
  if (removed.size === 0) return graph;
  const nodes = graph.nodes
    .filter((n) => !removed.has(n.id))
    .map((n) =>
      n.kind === "comment" && n.before !== null && removed.has(n.before)
        ? { ...n, before: null }
        : n,
    );
  const edges = graph.edges.filter((e) => !removed.has(e.from) && !removed.has(e.to));
  return { ...graph, nodes, edges };
}

/**
 * 方向键导航的上下游邻居：
 * 下一个 = seq 出边目标；无 seq 出边时（option_group/cond）取汇合点；jump/end 无下一个。
 * 上一个 = 入边源（seq 优先，否则 option/branch 源即组/条件节点）；start 无上一个。
 * 无法导航返回 null。
 */
export function flowNeighbor(graph: BgalsGraph, id: string, dir: 1 | -1): string | null {
  const idx = flowIndex(graph);
  const node = idx.nodes.get(id);
  if (!node) return null;
  if (dir === 1) {
    if (node.kind === "jump" || node.kind === "end") return null;
    const si = idx.seqOut.get(id);
    if (si !== undefined) return graph.edges[si].to;
    if (node.kind === "option_group" || node.kind === "cond") return findMerge(graph, id) ?? null;
    return null;
  }
  if (node.kind === "start") return null;
  const inc = idx.incoming.get(id) ?? [];
  if (inc.length === 0) return null;
  const seqInc = inc.find((i) => graph.edges[i].kind === "seq");
  return graph.edges[seqInc ?? inc[0]].from;
}

export function fail(message: string): never {
  throw new Error(message);
}

export function requireNode(graph: BgalsGraph, id: string): GraphNode {
  const node = graph.nodes.find((n) => n.id === id);
  if (!node) fail(`节点不存在: ${id}`);
  return node;
}

/** 整体替换同 id 节点 */
export function replaceNode(graph: BgalsGraph, node: GraphNode): BgalsGraph {
  return { ...graph, nodes: graph.nodes.map((n) => (n.id === node.id ? node : n)) };
}
