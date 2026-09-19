// 语义对比（回环校验核心）：投影后对比——剥节点 id（内容哈希对应）、剥 comment、剥布局。
// 边按（from 哈希, to 哈希, kind, text?, cond?）多重集合对比。

import type { BgalsGraph, GraphEdge, GraphNode } from "./graph";
import { contentHash } from "./sidecar";

export interface SemanticDiff {
  equal: boolean;
  diffs: string[];
}

interface Projection {
  nodeCounts: Map<string, number>;
  edgeCounts: Map<string, number>;
  nodeLabels: Map<string, string>;
  edgeLabels: Map<string, string>;
}

function truncate(text: string, max = 16): string {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function nodeLabel(n: GraphNode, out: GraphEdge[]): string {
  switch (n.kind) {
    case "dialogue":
      return `dialogue ${n.character ? `${n.character}：` : ""}「${truncate(n.text)}」`;
    case "inst":
      return `inst ${n.head}`;
    case "option_group":
      return `option_group（${out.filter((e) => e.kind === "option").length} 个选项）`;
    case "cond":
      return `cond（${out.filter((e) => e.kind === "branch").length} 条分支）`;
    case "jump":
      return `jump → ${n.target}`;
    case "comment":
      return `comment「${truncate(n.text)}」`;
    default:
      return n.kind;
  }
}

function project(graph: BgalsGraph): Projection {
  const hashOf = new Map<string, string>();
  const nodeLabels = new Map<string, string>();
  const nodeCounts = new Map<string, number>();
  for (const n of graph.nodes) {
    if (n.kind === "comment") continue;
    const out = graph.edges.filter((e) => e.from === n.id);
    const h = contentHash(n, out);
    hashOf.set(n.id, h);
    nodeCounts.set(h, (nodeCounts.get(h) ?? 0) + 1);
    if (!nodeLabels.has(h)) nodeLabels.set(h, nodeLabel(n, out));
  }
  const edgeCounts = new Map<string, number>();
  const edgeLabels = new Map<string, string>();
  for (const e of graph.edges) {
    const hf = hashOf.get(e.from);
    const ht = hashOf.get(e.to);
    if (hf === undefined || ht === undefined) continue;
    const key = `${hf}->${ht}|${e.kind}|${e.text ?? ""}|${e.cond ?? ""}`;
    edgeCounts.set(key, (edgeCounts.get(key) ?? 0) + 1);
    if (!edgeLabels.has(key)) {
      const label = `${e.kind} ${nodeLabels.get(hf)} → ${nodeLabels.get(ht)}`;
      edgeLabels.set(key, e.text ? `${label}「${truncate(e.text)}」` : label);
    }
  }
  return { nodeCounts, edgeCounts, nodeLabels, edgeLabels };
}

function diffMultiset(
  a: Map<string, number>,
  b: Map<string, number>,
  labels: Map<string, string>,
  onlyA: string,
  onlyB: string,
  diffs: string[],
): void {
  const keys = [...new Set([...a.keys(), ...b.keys()])].sort();
  for (const k of keys) {
    const d = (a.get(k) ?? 0) - (b.get(k) ?? 0);
    if (d === 0) continue;
    const label = labels.get(k) ?? k;
    const count = Math.abs(d) > 1 ? ` ×${Math.abs(d)}` : "";
    diffs.push(`${d > 0 ? onlyA : onlyB}：${label}${count}`);
  }
}

/** 语义投影对比：a 为基准（如图 → 文 → 编译 → dump 的回环中，a = 内存图，b = 回读图） */
export function semanticEqual(a: BgalsGraph, b: BgalsGraph): SemanticDiff {
  const pa = project(a);
  const pb = project(b);
  const diffs: string[] = [];
  const labels = new Map([...pa.nodeLabels, ...pb.nodeLabels]);
  diffMultiset(pa.nodeCounts, pb.nodeCounts, labels, "节点缺失", "节点多出", diffs);
  const eLabels = new Map([...pa.edgeLabels, ...pb.edgeLabels]);
  diffMultiset(pa.edgeCounts, pb.edgeCounts, eLabels, "边缺失", "边多出", diffs);
  return { equal: diffs.length === 0, diffs };
}
