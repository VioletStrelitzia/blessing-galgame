// 图编辑操作：全部纯函数，返回新图对象（不改入参）。
// 选项组/条件链操作见 graph_branch.ts，注释操作见 graph_comment.ts，此处统一再导出。

import { nanoid } from "nanoid";
import type {
  BgalsGraph,
  DialogueNode,
  GraphEdge,
  GraphNode,
  InstNode,
  InstPayload,
  JumpNode,
  Params,
} from "./graph";
import {
  DEFAULT_COND_BRANCHES,
  DEFAULT_OPTION_BRANCHES,
  branchEdge,
  type NodeDraft,
} from "./graph_branch";
import { removeComment } from "./graph_comment";
import { fail, findMerge, flowIndex, replaceNode, requireNode, sweepOrphans } from "./graph_walk";

export * from "./graph_branch";
export * from "./graph_comment";

/** 插入操作的输入：成品节点，或带默认分支的草稿（makeOptionGroup / makeCond 产出） */
export type Insertable = GraphNode | NodeDraft;

/** 指令槽元素（对话 prev/post 槽的编辑入参） */
export interface InstObj {
  head: string;
  params: Params;
}

function normalize(item: Insertable): NodeDraft {
  if ("node" in item) return item;
  // 裸组/条件节点按工厂默认分支接入
  if (item.kind === "option_group") return { node: item, branches: DEFAULT_OPTION_BRANCHES };
  if (item.kind === "cond") return { node: item, branches: DEFAULT_COND_BRANCHES };
  return { node: item, branches: [] };
}

function checkInsertable(graph: BgalsGraph, draft: NodeDraft): void {
  const { node } = draft;
  if (node.kind === "start" || node.kind === "end") fail("不能插入 start/end 节点");
  if (node.kind === "comment") fail("comment 节点不参与边，请用 addComment");
  if (graph.nodes.some((n) => n.id === node.id)) fail(`节点 id 已存在: ${node.id}`);
}

/** 新节点的出边：组/条件为指向汇合点的空体分支出边；jump 无出边；其余一条 seq */
function outEdgesOf(draft: NodeDraft, succ: string): GraphEdge[] {
  const { node, branches } = draft;
  if (node.kind === "option_group") {
    return branches.map((b) => branchEdge(node.id, succ, "option", b));
  }
  if (node.kind === "cond") return branches.map((b) => branchEdge(node.id, succ, "branch", b));
  if (node.kind === "jump") return [];
  return [{ from: node.id, to: succ, kind: "seq" }];
}

function insertNodeAfter(nodes: GraphNode[], afterId: string, node: GraphNode): GraphNode[] {
  const i = nodes.findIndex((n) => n.id === afterId);
  const out = nodes.slice();
  out.splice(i < 0 ? out.length : i + 1, 0, node);
  return out;
}

/** 拆一条 seq 边：from→node、node→to（组/条件为指向 to 的空体分支；jump 无出边） */
function spliceOnSeqEdge(graph: BgalsGraph, edgeIndex: number, draft: NodeDraft): BgalsGraph {
  const e = graph.edges[edgeIndex];
  const edges = graph.edges.slice();
  edges[edgeIndex] = { from: e.from, to: draft.node.id, kind: "seq" };
  edges.splice(edgeIndex + 1, 0, ...outEdgesOf(draft, e.to));
  return { ...graph, nodes: insertNodeAfter(graph.nodes, e.from, draft.node), edges };
}

export function insertOnEdge(graph: BgalsGraph, edgeIndex: number, item: Insertable): BgalsGraph {
  const e = graph.edges[edgeIndex];
  if (!e) fail(`边下标越界: ${edgeIndex}`);
  if (e.kind !== "seq") fail("只能在 seq 顺序边上插入节点");
  const draft = normalize(item);
  checkInsertable(graph, draft);
  if (draft.node.kind === "jump") {
    fail("jump 是终端节点，不能插在 seq 边中间（请用 appendEnd/appendAfter 处理终端跳转）");
  }
  return spliceOnSeqEdge(graph, edgeIndex, draft);
}

export function appendAfter(graph: BgalsGraph, nodeId: string, item: Insertable): BgalsGraph {
  const target = requireNode(graph, nodeId);
  const draft = normalize(item);
  checkInsertable(graph, draft);
  if (target.kind === "jump") fail("jump 是终端节点，其后不能追加节点");
  if (target.kind === "end") fail("end 之后不能追加节点");
  const idx = flowIndex(graph);

  if (target.kind === "option_group" || target.kind === "cond") {
    const merge = findMerge(graph, nodeId);
    if (!merge) fail(`节点 ${nodeId} 没有汇合点（所有分支均已跳转），无法在其后插入`);
    // 新节点成为新汇合点：原指向汇合点的入边全部改指新节点，新节点再接原汇合点
    const edges = graph.edges.map((e) =>
      e.to === merge && e.kind !== "jump" ? { ...e, to: draft.node.id } : e,
    );
    edges.push(...outEdgesOf(draft, merge));
    return { ...graph, nodes: insertNodeAfter(graph.nodes, nodeId, draft.node), edges };
  }

  const seqIdx = idx.seqOut.get(nodeId);
  if (seqIdx !== undefined) {
    if (draft.node.kind === "jump") {
      fail("jump 是终端节点，不能插在 seq 边中间（请追加到无后继的节点之后）");
    }
    const e = graph.edges[seqIdx];
    const edges = graph.edges.slice();
    edges[seqIdx] = { from: e.from, to: draft.node.id, kind: "seq" };
    edges.splice(seqIdx + 1, 0, ...outEdgesOf(draft, e.to));
    return { ...graph, nodes: insertNodeAfter(graph.nodes, nodeId, draft.node), edges };
  }
  // 无 seq 后继（尾节点）：直接接尾；非终端新节点续到 end
  if (!idx.endId) fail("图缺少 end 节点");
  const edges = graph.edges.slice();
  edges.push({ from: nodeId, to: draft.node.id, kind: "seq" });
  if (draft.node.kind !== "jump") edges.push(...outEdgesOf(draft, idx.endId));
  return { ...graph, nodes: insertNodeAfter(graph.nodes, nodeId, draft.node), edges };
}

/** 追加到主流程结尾：split 主链上进入 end 的那条 seq 边 */
export function appendEnd(graph: BgalsGraph, item: Insertable): BgalsGraph {
  const idx = flowIndex(graph);
  if (!idx.startId || !idx.endId) fail("图缺少 start/end 节点");
  let cur = idx.startId;
  let lastSeq: number | undefined;
  const seen = new Set<string>();
  while (cur !== idx.endId && !seen.has(cur)) {
    seen.add(cur);
    const si = idx.seqOut.get(cur);
    if (si === undefined) break;
    lastSeq = si;
    cur = graph.edges[si].to;
  }
  if (cur !== idx.endId || lastSeq === undefined) {
    fail("主流程未到达 end，无法定位结尾（请改用 appendAfter）");
  }
  const draft = normalize(item);
  checkInsertable(graph, draft);
  return spliceOnSeqEdge(graph, lastSeq, draft);
}

export function removeNode(graph: BgalsGraph, id: string): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind === "start" || node.kind === "end") fail("start/end 节点不可删除");
  if (node.kind === "comment") return removeComment(graph, id);
  const idx = flowIndex(graph);

  if (node.kind === "option_group" || node.kind === "cond") {
    // 连带删除独占子图（孤悬清扫），前驱与汇合后继重连
    const merge = findMerge(graph, id) ?? idx.endId;
    if (!merge) fail(`节点 ${id} 无汇合点且图中没有 end 节点，无法重连`);
    const edges = graph.edges
      .filter((e) => e.from !== id)
      .map((e) => (e.to === id ? { ...e, to: merge } : e));
    return sweepOrphans({ ...graph, nodes: graph.nodes.filter((n) => n.id !== id), edges });
  }

  const seqIdx = idx.seqOut.get(id);
  const succ = seqIdx !== undefined ? graph.edges[seqIdx].to : undefined;
  let edges = graph.edges.filter((e) => e.from !== id);
  if (succ !== undefined) {
    // 前驱 → 后继重连（option/branch 入边改指后继，保持空体形态）
    edges = edges.map((e) => (e.to === id ? { ...e, to: succ } : e));
  } else {
    // 终端节点（jump）：seq 入边删除；option/branch 入边改指所属组的汇合点
    edges = edges.flatMap((e) => {
      if (e.to !== id) return [e];
      if (e.kind === "seq") return [];
      const merge = findMerge(graph, e.from) ?? idx.endId;
      return merge ? [{ ...e, to: merge }] : [];
    });
  }
  const nodes = graph.nodes
    .filter((n) => n.id !== id)
    .map((n) => (n.kind === "comment" && n.before === id ? { ...n, before: null } : n));
  return { ...graph, nodes, edges };
}

export function updateDialogue(
  graph: BgalsGraph,
  id: string,
  patch: { character?: string; text?: string },
): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind !== "dialogue") fail(`节点 ${id} 不是 dialogue（实际 ${node.kind}）`);
  const next: DialogueNode = { ...node };
  if (patch.character !== undefined) next.character = patch.character;
  if (patch.text !== undefined) {
    next.text = patch.text;
    // 派生字段随原文失效，待下次 dump 重建
    next.display_text = patch.text;
    next.anchors = [];
  }
  return replaceNode(graph, next);
}

/** 整体替换 params 对象 */
export function updateInstParams(graph: BgalsGraph, id: string, params: Params): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind !== "inst") fail(`节点 ${id} 不是 inst（实际 ${node.kind}）`);
  return replaceNode(graph, { ...node, params: { ...params } });
}

/** 编辑对话前/后指令槽（整体替换） */
export function setSlot(
  graph: BgalsGraph,
  dialogueId: string,
  slot: "prev" | "post",
  list: InstObj[],
): BgalsGraph {
  const node = requireNode(graph, dialogueId);
  if (node.kind !== "dialogue") fail(`节点 ${dialogueId} 不是 dialogue（实际 ${node.kind}）`);
  const payload: InstPayload[] = list.map((i) => ({
    kind: "inst",
    head: i.head,
    params: { ...i.params },
  }));
  return replaceNode(
    graph,
    slot === "prev" ? { ...node, prev: payload } : { ...node, post: payload },
  );
}

export function updateJump(graph: BgalsGraph, id: string, target: string): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind !== "jump") fail(`节点 ${id} 不是 jump（实际 ${node.kind}）`);
  if (!target.trim()) fail("jump 目标不能为空");
  return replaceNode(graph, { ...node, target });
}

export function makeDialogue(id = nanoid(8)): DialogueNode {
  return {
    id,
    kind: "dialogue",
    character: "",
    text: "",
    display_text: "",
    anchors: [],
    prev: [],
    post: [],
  };
}

export function makeInst(head: string, id = nanoid(8)): InstNode {
  return { id, kind: "inst", head, params: {} };
}

export function makeJump(target: string, id = nanoid(8)): JumpNode {
  return { id, kind: "jump", target };
}
