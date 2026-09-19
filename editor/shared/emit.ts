// 图 → BGalS 文本发射器（纯函数；web/server 共用，M2 导出与回环校验的核心）。
// 走查：start 沿 seq 边拓扑前进；option_group/cond 的体按 spec.indent_unit 缩进内联展开。
// 汇合点判定：各分支共同可达、距组头最近（BFS）的节点；分支含 jump 时可能无汇合点，
// 此时后续内容由唯一可达它的分支自然吞并（语义等价，见设计文档「导出」节）。
// comment 节点不参与边，发射 `# text` 行于其 before 节点首行之前（before=null 放文件头）。

import type { BgalsGraph, CommentNode, GraphEdge, GraphNode, InstPayload, Params } from "./graph";
import { STRUCTURAL_HEADS } from "./graph";
import type { BgalsSpec, SpecParam } from "./spec";

function fmtValue(v: Params[string]): string {
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") return String(v);
  return v === "" || /\s/.test(v) ? `"${v}"` : v;
}

function joinParts(...parts: (string | null)[]): string {
  return parts.filter((p): p is string => p !== null && p !== "").join(" ");
}

interface Ctx {
  inst: InstPayload;
  spec: BgalsSpec;
}

function specParam(ctx: Ctx, name: string): SpecParam | undefined {
  return ctx.spec.spec[ctx.inst.head]?.find((p) => p.name === name);
}

/** 位置参数：params 缺省时回退 spec 默认值（dump 省略默认值，但文本位次不可缺）；required=false 的可省略 */
function pos(ctx: Ctx, name: string, required = true): string | null {
  const sp = specParam(ctx, name);
  const v = ctx.inst.params[name];
  if (v === undefined) {
    if (!required) return null;
    const dflt = sp?.default;
    return dflt === undefined || Array.isArray(dflt) ? null : fmtValue(dflt);
  }
  if (!required && sp && v === sp.default) return null;
  return fmtValue(v);
}

/** 键值参数：仅写非默认值（dump 已省略，此处再挡一次） */
function kv(ctx: Ctx, name: string, key = name): string | null {
  const sp = specParam(ctx, name);
  const v = ctx.inst.params[name];
  if (v === undefined || (sp !== undefined && v === sp.default)) return null;
  return `${key}:${fmtValue(v)}`;
}

function xy(ctx: Ctx): string {
  return `${pos(ctx, "x") ?? "0"},${pos(ctx, "y") ?? "0"}`;
}

type InstEmitter = (ctx: Ctx) => string | null;

const INST_EMITTERS: Record<string, InstEmitter> = {
  SET_BACKGROUND: (c) => joinParts("bg", pos(c, "path"), kv(c, "time")),
  MUSIC_PLAY: (c) =>
    joinParts(
      "music",
      pos(c, "path"),
      kv(c, "from"),
      kv(c, "loop"),
      kv(c, "fade_in"),
      kv(c, "fade_out"),
      kv(c, "volume"),
    ),
  MUSIC_STOP: (c) => joinParts("music stop", kv(c, "fade")),
  MUSIC_PAUSE: () => "music pause",
  MUSIC_RESUME: () => "music resume",
  MUSIC_VOLUME: (c) => joinParts("music volume", pos(c, "volume"), kv(c, "fade")),
  VOICE_PLAY: (c) => joinParts("voice", pos(c, "path"), kv(c, "from"), kv(c, "volume")),
  VOICE_STOP: (c) => joinParts("voice stop", kv(c, "fade")),
  SFX_PLAY: (c) => joinParts("sfx", pos(c, "path"), kv(c, "from"), kv(c, "volume"), kv(c, "loop")),
  SFX_STOP: (c) => joinParts("sfx stop", pos(c, "ref", false), kv(c, "fade")),
  SFX_VOLUME: (c) => joinParts("sfx volume", pos(c, "ref"), pos(c, "volume"), kv(c, "fade")),
  CHAR_SETUP: (c) => joinParts("char", pos(c, "char_index"), "setup", pos(c, "path"), xy(c)),
  CHAR_SHOW_FADE: (c) =>
    joinParts("char", pos(c, "char_index"), "show", kv(c, "duration", "time"), kv(c, "wait")),
  CHAR_HIDE_FADE: (c) =>
    joinParts("char", pos(c, "char_index"), "hide", kv(c, "duration", "time"), kv(c, "wait")),
  CHAR_MOVE_TO: (c) =>
    joinParts(
      "char",
      pos(c, "char_index"),
      "move",
      xy(c),
      kv(c, "duration", "time"),
      kv(c, "wait"),
    ),
  CHAR_WAIT: (c) => joinParts("char", pos(c, "char_index"), "wait", pos(c, "duration")),
  CHAR_CHANGE_TEXTURE: (c) => joinParts("char", pos(c, "char_index"), "texture", pos(c, "path")),
  VAR_SET: (c) => joinParts("var", pos(c, "key"), "=", pos(c, "value")),
  VAR_ADD: (c) => joinParts("var", pos(c, "key"), "+=", pos(c, "value")),
  VAR_SUB: (c) => joinParts("var", pos(c, "key"), "-=", pos(c, "value")),
  VAR_MUL: (c) => joinParts("var", pos(c, "key"), "*=", pos(c, "value")),
  VAR_DIV: (c) => joinParts("var", pos(c, "key"), "/=", pos(c, "value")),
  VAR_RANDOM: (c) => joinParts("var", pos(c, "key"), "= random", pos(c, "min"), pos(c, "max")),
  SET_BEGIN_SCRIPT: (c) => joinParts("begin", pos(c, "script_name")),
  JUMP_SCRIPT: (c) => joinParts("jump", pos(c, "script_name")),
  JUMP_MAIN_MENU: () => "jump main_menu",
  SCENE_MOUNT: (c) =>
    joinParts(
      "scene mount",
      pos(c, "type"),
      pos(c, "name"),
      pos(c, "path"),
      kv(c, "time"),
      kv(c, "anim"),
    ),
  SCENE_UNMOUNT: (c) =>
    joinParts(
      "scene unmount",
      pos(c, "type"),
      pos(c, "name"),
      kv(c, "time"),
      kv(c, "anim"),
      kv(c, "free"),
    ),
  TRANSITION_IN: (c) => joinParts("trans in", kv(c, "time"), kv(c, "anim"), kv(c, "wait")),
  TRANSITION_OUT: (c) => joinParts("trans out", kv(c, "time"), kv(c, "anim"), kv(c, "wait")),
  WAIT: (c) => joinParts("wait", pos(c, "duration")),
};

/** 单条指令 → 文本行；结构指令返回 null，未知指令头返回注释行（可见的降级，不静默丢数据） */
export function emitInst(inst: InstPayload, spec: BgalsSpec): string | null {
  if (STRUCTURAL_HEADS.has(inst.head)) return null;
  const emitter = INST_EMITTERS[inst.head];
  if (!emitter) return `# 未识别指令头: ${inst.head}`;
  return emitter({ inst, spec });
}

/** 行首保留字符（保留字、* > < # /）会被解析为指令/选项/注释，对话行需补 \ 转义 */
export function escapeDialogueLine(line: string, spec: BgalsSpec): string {
  const firstWord = line.split(/[ \t]/, 1)[0];
  if (/^[*><#/]/.test(line) || spec.reserved_keys.includes(firstWord)) return "\\" + line;
  return line;
}

export interface EmitResult {
  text: string;
  /** 节点 id → 其产出的全部行范围（1 起始，含首尾；comment 节点同样记录；未产出行的节点无条目） */
  lineMap: Record<string, { from: number; to: number }>;
}

export function emitGraph(graph: BgalsGraph, spec: BgalsSpec): EmitResult {
  const nodes = new Map<string, GraphNode>(graph.nodes.map((n) => [n.id, n]));
  const start = graph.nodes.find((n) => n.kind === "start");
  if (!start) throw new Error("图缺少 start 节点");
  const seqNext = new Map<string, string>();
  const branchEdges = new Map<string, GraphEdge[]>();
  for (const e of graph.edges) {
    if (e.kind === "seq") {
      if (!seqNext.has(e.from)) seqNext.set(e.from, e.to);
    } else if (e.kind === "option" || e.kind === "branch") {
      const list = branchEdges.get(e.from) ?? [];
      list.push(e);
      branchEdges.set(e.from, list);
    }
  }

  // 注释按附着目标分桶；目标缺失的降级到文件头（可见的降级，不静默丢数据）
  const comments = graph.nodes.filter((n): n is CommentNode => n.kind === "comment");
  const commentBucket = new Map<string, CommentNode[]>();
  const pendingComments = new Set<string>();
  for (const c of comments) {
    pendingComments.add(c.id);
    const key = c.before !== null && nodes.has(c.before) ? c.before : "";
    const list = commentBucket.get(key) ?? [];
    list.push(c);
    commentBucket.set(key, list);
  }

  const unit = " ".repeat(spec.indent_unit > 0 ? spec.indent_unit : 4);
  const lines: string[] = [];
  const lineMap: EmitResult["lineMap"] = {};
  const consumed = new Set<string>(
    graph.nodes.filter((n) => n.kind === "start" || n.kind === "end").map((n) => n.id),
  );

  const emitComment = (c: CommentNode, pad: string) => {
    if (!pendingComments.has(c.id)) return;
    pendingComments.delete(c.id);
    lines.push(`${pad}# ${c.text}`);
    lineMap[c.id] = { from: lines.length, to: lines.length };
  };

  for (const c of commentBucket.get("") ?? []) emitComment(c, "");

  const reachable = (from: string): Set<string> => {
    const seen = new Set<string>();
    const stack = [from];
    while (stack.length > 0) {
      const id = stack.pop()!;
      if (seen.has(id)) continue;
      seen.add(id);
      const next = seqNext.get(id);
      if (next !== undefined) stack.push(next);
      for (const b of branchEdges.get(id) ?? []) stack.push(b.to);
    }
    return seen;
  };

  const findMerge = (from: string, targets: string[]): string | undefined => {
    if (targets.length === 0) return undefined;
    let common = reachable(targets[0]);
    for (const t of targets.slice(1)) {
      const r = reachable(t);
      common = new Set([...common].filter((id) => r.has(id)));
    }
    if (common.size === 0) return undefined;
    const queue = [from];
    const seen = new Set<string>([from]);
    while (queue.length > 0) {
      const id = queue.shift()!;
      const nexts: string[] = [];
      const s = seqNext.get(id);
      if (s !== undefined) nexts.push(s);
      for (const b of branchEdges.get(id) ?? []) nexts.push(b.to);
      for (const n of nexts) {
        if (seen.has(n)) continue;
        if (common.has(n)) return n;
        seen.add(n);
        queue.push(n);
      }
    }
    return undefined;
  };

  const emitSeq = (startId: string | undefined, indent: number, stops: ReadonlySet<string>) => {
    const pad = unit.repeat(indent);
    let cur = startId;
    while (cur !== undefined && !consumed.has(cur) && !stops.has(cur)) {
      const node = nodes.get(cur);
      if (!node) return;
      consumed.add(cur);
      for (const c of commentBucket.get(cur) ?? []) emitComment(c, pad);
      const from = lines.length + 1;
      let next: string | undefined = seqNext.get(cur);
      if (node.kind === "dialogue") {
        for (const ins of node.prev) {
          const line = emitInst(ins, spec);
          if (line) lines.push(`${pad}< ${line}`);
        }
        const raw = node.character ? `${node.character}: ${node.text}` : node.text;
        lines.push(pad + escapeDialogueLine(raw, spec));
        for (const ins of node.post) {
          const line = emitInst(ins, spec);
          if (line) lines.push(`${pad}> ${line}`);
        }
      } else if (node.kind === "inst") {
        const line = emitInst(node, spec);
        if (line) lines.push(pad + line);
      } else if (node.kind === "jump") {
        lines.push(`${pad}jump ${node.target}`);
        next = undefined; // 终端节点：跳转即卸载，无 seq 后继
      } else if (node.kind === "option_group" || node.kind === "cond") {
        const edges = branchEdges.get(cur) ?? [];
        const merge = findMerge(
          cur,
          edges.map((e) => e.to),
        );
        const bodyStops = new Set(stops);
        if (merge !== undefined) bodyStops.add(merge);
        edges.forEach((e, i) => {
          if (node.kind === "option_group") {
            lines.push(`${pad}* ${e.text ?? ""}${e.cond ? ` if:${e.cond}` : ""}`);
          } else {
            const kw = i === 0 ? "if" : e.cond ? "elif" : "else";
            lines.push(pad + (e.cond ? `${kw} ${e.cond}` : kw));
          }
          emitSeq(e.to, indent + 1, bodyStops);
        });
        next = merge;
      }
      if (lines.length >= from) lineMap[cur] = { from, to: lines.length };
      cur = next;
    }
  };

  emitSeq(seqNext.get(start.id), 0, new Set());
  // 附着目标未走查到（不可达）的注释收尾到文件尾
  for (const c of comments) emitComment(c, "");
  return { text: lines.join("\n") + "\n", lineMap };
}
