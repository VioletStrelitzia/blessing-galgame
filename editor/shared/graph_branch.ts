// 选项组 / 条件链的分支编辑操作与对应工厂。分支序 = 该节点出边在 edges 数组中的相对顺序。

import { nanoid } from "nanoid";
import type { BgalsGraph, CondNode, GraphEdge, GraphNode, OptionGroupNode } from "./graph";
import { fail, flowIndex, requireNode, successorOf, sweepOrphans } from "./graph_walk";

/** 新节点的默认分支草稿（to 由插入操作解析为后继汇合点，空体合法） */
export interface BranchDraft {
  text?: string;
  cond?: string;
}

export interface NodeDraft<N extends GraphNode = GraphNode> {
  node: N;
  branches: BranchDraft[];
}

export const DEFAULT_OPTION_BRANCHES: BranchDraft[] = [{ text: "选项 1" }, { text: "选项 2" }];
export const DEFAULT_COND_BRANCHES: BranchDraft[] = [{ cond: "true" }, {}];

export function branchEdge(
  from: string,
  to: string,
  kind: "option" | "branch",
  draft: BranchDraft,
): GraphEdge {
  const e: GraphEdge = { from, to, kind };
  if (draft.text !== undefined) e.text = draft.text;
  if (draft.cond !== undefined) e.cond = draft.cond;
  return e;
}

/** 校验 edges[edgeIndex] 确为 groupId 的指定类型出边 */
function requireBranchEdge(
  graph: BgalsGraph,
  groupId: string,
  edgeIndex: number,
  kind: "option" | "branch",
): GraphEdge {
  const e = graph.edges[edgeIndex];
  if (!e) fail(`边下标越界: ${edgeIndex}`);
  if (e.from !== groupId || e.kind !== kind) {
    fail(`边 #${edgeIndex} 不是节点 ${groupId} 的 ${kind} 出边`);
  }
  return e;
}

/** 组内分支出边的 edges 下标列表（数组序） */
function branchIndices(graph: BgalsGraph, groupId: string, kind: "option" | "branch"): number[] {
  return (flowIndex(graph).branchOut.get(groupId) ?? []).filter(
    (i) => graph.edges[i].kind === kind,
  );
}

export function addOption(
  graph: BgalsGraph,
  groupId: string,
  draft: { text: string; cond?: string },
): BgalsGraph {
  if (requireNode(graph, groupId).kind !== "option_group") fail(`节点 ${groupId} 不是选项组`);
  const merge = successorOf(graph, groupId);
  if (!merge) fail(`选项组 ${groupId} 没有汇合点（所有分支均已跳转），无法添加空选项`);
  const edge = branchEdge(groupId, merge, "option", draft);
  const edges = graph.edges.slice();
  const list = branchIndices(graph, groupId, "option");
  edges.splice(list.length > 0 ? list[list.length - 1] + 1 : edges.length, 0, edge);
  return { ...graph, edges };
}

export function updateOption(
  graph: BgalsGraph,
  groupId: string,
  edgeIndex: number,
  patch: { text?: string; cond?: string | null },
): BgalsGraph {
  requireBranchEdge(graph, groupId, edgeIndex, "option");
  const edges = graph.edges.slice();
  const next = { ...edges[edgeIndex] };
  if (patch.text !== undefined) next.text = patch.text;
  if (patch.cond !== undefined) {
    if (patch.cond === null || patch.cond === "") delete next.cond;
    else next.cond = patch.cond;
  }
  edges[edgeIndex] = next;
  return { ...graph, edges };
}

export function removeOption(graph: BgalsGraph, groupId: string, edgeIndex: number): BgalsGraph {
  requireNode(graph, groupId);
  requireBranchEdge(graph, groupId, edgeIndex, "option");
  const list = branchIndices(graph, groupId, "option");
  if (list.length > 1) {
    // 删该分支边，其独占子图随孤悬清扫收敛
    return sweepOrphans({ ...graph, edges: graph.edges.filter((_, i) => i !== edgeIndex) });
  }
  // 剩 0 条：连组删掉，全部入边改指汇合点（= 最后一条分支的体头，相当于内联展开）
  const merge = successorOf(graph, groupId) ?? flowIndex(graph).endId;
  if (!merge) fail(`选项组 ${groupId} 无汇合点且图中没有 end 节点，无法重连`);
  const edges = graph.edges
    .filter((e) => e.from !== groupId)
    .map((e) => (e.to === groupId ? { ...e, to: merge } : e));
  return sweepOrphans({ ...graph, nodes: graph.nodes.filter((n) => n.id !== groupId), edges });
}

export function moveOption(
  graph: BgalsGraph,
  groupId: string,
  edgeIndex: number,
  dir: -1 | 1,
): BgalsGraph {
  requireBranchEdge(graph, groupId, edgeIndex, "option");
  const list = branchIndices(graph, groupId, "option");
  const pos = list.indexOf(edgeIndex);
  const swap = pos + dir;
  if (pos < 0 || swap < 0 || swap >= list.length)
    fail(`选项已在边界，无法${dir < 0 ? "上移" : "下移"}`);
  const edges = graph.edges.slice();
  [edges[edgeIndex], edges[list[swap]]] = [edges[list[swap]], edges[edgeIndex]];
  return { ...graph, edges };
}

export function addBranch(graph: BgalsGraph, condId: string, cond: string): BgalsGraph {
  if (requireNode(graph, condId).kind !== "cond") fail(`节点 ${condId} 不是条件链`);
  if (!cond.trim()) fail("elif 分支条件不能为空");
  const merge = successorOf(graph, condId);
  if (!merge) fail(`条件链 ${condId} 没有汇合点（所有分支均已跳转），无法添加空分支`);
  const edge = branchEdge(condId, merge, "branch", { cond });
  const edges = graph.edges.slice();
  const list = branchIndices(graph, condId, "branch");
  // 插到 else（无 cond 的分支边）之前；无 else 则追加在末位分支之后
  const elseIdx = list.find((i) => graph.edges[i].cond === undefined);
  edges.splice(elseIdx ?? (list.length > 0 ? list[list.length - 1] + 1 : edges.length), 0, edge);
  return { ...graph, edges };
}

export function updateBranch(
  graph: BgalsGraph,
  condId: string,
  edgeIndex: number,
  cond: string,
): BgalsGraph {
  const e = requireBranchEdge(graph, condId, edgeIndex, "branch");
  if (e.cond === undefined) fail("else 分支不可设置条件");
  if (!cond.trim()) fail("分支条件不能为空");
  const edges = graph.edges.slice();
  edges[edgeIndex] = { ...e, cond };
  return { ...graph, edges };
}

export function removeBranch(graph: BgalsGraph, condId: string, edgeIndex: number): BgalsGraph {
  requireNode(graph, condId);
  requireBranchEdge(graph, condId, edgeIndex, "branch");
  if (branchIndices(graph, condId, "branch").length <= 1) fail("条件链至少保留一条分支，无法删除");
  return sweepOrphans({ ...graph, edges: graph.edges.filter((_, i) => i !== edgeIndex) });
}

export function makeOptionGroup(id = nanoid(8)): NodeDraft<OptionGroupNode> {
  return { node: { id, kind: "option_group" }, branches: DEFAULT_OPTION_BRANCHES };
}

export function makeCond(cond: string, id = nanoid(8)): NodeDraft<CondNode> {
  return { node: { id, kind: "cond" }, branches: [{ cond }, {}] };
}
