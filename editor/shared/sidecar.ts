// sidecar（.graph.json）：编辑器工程数据（布局 + 注释），引擎永远不读。
// 节点身份用内容哈希匹配（dump 的节点 id 会随文本漂移），同哈希多节点按出现顺序配对。

import type {
  BgalsGraph,
  CommentNode,
  GraphEdge,
  GraphNode,
  InstPayload,
  Params,
  ParamValue,
} from "./graph";

export interface SidecarLayout {
  hash: string;
  x: number;
  y: number;
}

export interface SidecarComment {
  id: string;
  text: string;
  beforeHash: string | null;
}

export interface Sidecar {
  format: "bgals-editor/1";
  compiler: string;
  script: string;
  layout: SidecarLayout[];
  comments: SidecarComment[];
}

function djb2(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = (h * 33 + s.charCodeAt(i)) >>> 0;
  return h.toString(16).padStart(8, "0");
}

function sortedParams(p: Params): Array<[string, ParamValue]> {
  return Object.keys(p)
    .sort()
    .map((k) => [k, p[k]]);
}

function instCanon(i: InstPayload): unknown {
  return [i.head, sortedParams(i.params)];
}

/** 节点语义字段的稳定序列化 → djb2 十六进制（不含 id/坐标；组/条件含分支 text+cond 列表） */
export function contentHash(node: GraphNode, outEdges: GraphEdge[] = []): string {
  let canon: unknown;
  switch (node.kind) {
    case "inst":
      canon = [node.kind, node.head, sortedParams(node.params)];
      break;
    case "dialogue":
      canon = [
        node.kind,
        node.character,
        node.text,
        node.prev.map(instCanon),
        node.post.map(instCanon),
      ];
      break;
    case "option_group":
      canon = [
        node.kind,
        outEdges.filter((e) => e.kind === "option").map((e) => [e.text ?? "", e.cond ?? null]),
      ];
      break;
    case "cond":
      canon = [node.kind, outEdges.filter((e) => e.kind === "branch").map((e) => e.cond ?? null)];
      break;
    case "jump":
      canon = [node.kind, node.target];
      break;
    case "comment":
      canon = [node.kind, node.text];
      break;
    default:
      canon = [node.kind];
  }
  return djb2(JSON.stringify(canon));
}

function hashOf(graph: BgalsGraph, node: GraphNode): string {
  return contentHash(
    node,
    graph.edges.filter((e) => e.from === node.id),
  );
}

export function buildSidecar(
  graph: BgalsGraph,
  positions: Map<string, { x: number; y: number }>,
  compiler = graph.compiler,
  script = graph.script,
): Sidecar {
  const byId = new Map(graph.nodes.map((n) => [n.id, n]));
  const layout: SidecarLayout[] = [];
  const comments: SidecarComment[] = [];
  for (const n of graph.nodes) {
    if (n.kind === "comment") {
      const target = n.before !== null ? byId.get(n.before) : undefined;
      comments.push({
        id: n.id,
        text: n.text,
        beforeHash: target ? hashOf(graph, target) : null,
      });
    }
    const p = positions.get(n.id);
    if (p) layout.push({ hash: hashOf(graph, n), x: p.x, y: p.y });
  }
  return { format: "bgals-editor/1", compiler, script, layout, comments };
}

/** hash → 候选 id 队列（按出现顺序，shift 消费；同哈希多节点由此确定性配对） */
function queueOf(entries: Array<[string, string]>): Map<string, string[]> {
  const m = new Map<string, string[]>();
  for (const [hash, id] of entries) {
    const q = m.get(hash) ?? [];
    q.push(id);
    m.set(hash, q);
  }
  return m;
}

export function applySidecar(
  graph: BgalsGraph,
  sidecar: Sidecar,
): { positions: Map<string, { x: number; y: number }>; comments: CommentNode[] } {
  if (sidecar.format !== "bgals-editor/1") failFormat(sidecar.format);

  // 布局配对队列：图节点（不含 comment）+ sidecar 注释节点，各自按出现顺序
  const layoutQueue = queueOf(
    graph.nodes.filter((n) => n.kind !== "comment").map((n) => [hashOf(graph, n), n.id]),
  );
  const comments: CommentNode[] = sidecar.comments.map((c) => ({
    id: c.id,
    kind: "comment",
    text: c.text,
    before: null,
  }));
  for (const c of comments) {
    const q = layoutQueue.get(contentHash(c)) ?? [];
    q.push(c.id);
    layoutQueue.set(contentHash(c), q);
  }

  const positions = new Map<string, { x: number; y: number }>();
  for (const l of sidecar.layout) {
    const id = layoutQueue.get(l.hash)?.shift();
    if (id !== undefined) positions.set(id, { x: l.x, y: l.y });
  }

  // 注释附着：beforeHash 按出现顺序配对图节点，匹配不到则降级为 null（文件头）
  const beforeQueue = queueOf(
    graph.nodes.filter((n) => n.kind !== "comment").map((n) => [hashOf(graph, n), n.id]),
  );
  sidecar.comments.forEach((c, i) => {
    if (c.beforeHash === null) return;
    const before = beforeQueue.get(c.beforeHash)?.shift();
    if (before !== undefined) comments[i] = { ...comments[i], before };
  });

  return { positions, comments };
}

function failFormat(format: string): never {
  throw new Error(`未知 sidecar 格式: ${format}`);
}
