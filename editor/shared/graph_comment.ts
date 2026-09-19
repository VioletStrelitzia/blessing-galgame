// 注释节点操作：不参与边，before = 附着目标节点 id（null = 文件头）。

import { nanoid } from "nanoid";
import type { BgalsGraph, CommentNode } from "./graph";
import { fail, replaceNode, requireNode } from "./graph_walk";

export function makeComment(text: string, id = nanoid(8)): CommentNode {
  return { id, kind: "comment", text, before: null };
}

/** 新增注释；id 可显式指定（默认 nanoid(8)），便于调用方先知先觉 */
export function addComment(
  graph: BgalsGraph,
  beforeId: string | null,
  text: string,
  id = nanoid(8),
): BgalsGraph {
  if (beforeId !== null) requireNode(graph, beforeId);
  if (graph.nodes.some((n) => n.id === id)) fail(`节点 id 已存在: ${id}`);
  return { ...graph, nodes: [...graph.nodes, { id, kind: "comment", text, before: beforeId }] };
}

export function updateComment(graph: BgalsGraph, id: string, text: string): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind !== "comment") fail(`节点 ${id} 不是 comment（实际 ${node.kind}）`);
  return replaceNode(graph, { ...node, text });
}

export function removeComment(graph: BgalsGraph, id: string): BgalsGraph {
  const node = requireNode(graph, id);
  if (node.kind !== "comment") fail(`节点 ${id} 不是 comment（实际 ${node.kind}）`);
  return { ...graph, nodes: graph.nodes.filter((n) => n.id !== id) };
}
