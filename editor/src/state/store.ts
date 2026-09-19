// 编辑器领域状态（zustand）：图是唯一事实源，React Flow 仅为视图投影。
// 所有图变更经 mutateGraph（调 graph_ops 纯函数 → 压撤销快照 cap 100 → 置 dirty）；
// 位置 Map 独立存放，不进撤销栈，但参与 dirty 判定（sidecar 内容）。
// IO 动作（init/openScript/save/check/verify）见 state/io.ts，编辑动作见 state/edit.ts。

import { create } from "zustand";
import { scriptNameOfFile, type CheckReport } from "../../shared/check";
import { emitGraph } from "../../shared/emit";
import type { BgalsGraph } from "../../shared/graph";
import type { BgalsSpec } from "../../shared/spec";
import type { ModeInfo, RefsData } from "../api";
import { stackPositions } from "../graph/collapse";
import { fillMissingPositions, type Pos } from "../graph/layout";
import type { DiagBadge } from "../graph/toFlow";

export type { Pos };

export const UNDO_CAP = 100;
/** 相同 tag 的连续变更（如逐键输入）在该窗口内合并为一个撤销步 */
const COALESCE_MS = 800;

export interface InsertMenuState {
  /** null = 末尾追加模式；否则为 graph.edges 下标（seq 边插入） */
  edgeIndex: number | null;
  x: number;
  y: number;
}

export interface VerifyState {
  equal: boolean;
  diffs: string[];
  at: number;
}

export interface EditorState {
  spec: BgalsSpec | null;
  refs: RefsData | null;
  mode: ModeInfo["mode"];
  devMode: boolean;
  scripts: string[];
  current: string | null;
  graph: BgalsGraph | null;
  positions: Map<string, Pos>;
  selected: string | null;
  /** 诊断面板点击后的画布定位请求（n 为触发序号） */
  focusReq: { id: string; n: number } | null;
  report: CheckReport | null;
  /** 与 report.diags 对齐的节点归属（null = 不属于当前剧本或无法定位） */
  diagNode: (string | null)[];
  nodeDiags: Record<string, DiagBadge>;
  verifyResult: VerifyState | null;
  dirty: boolean;
  lastSaved: string | null;
  undoStack: BgalsGraph[];
  redoStack: BgalsGraph[];
  /** 已展开的聚合链（group:<首节点 id> 集合，视图层状态，随剧本切换清空） */
  expandedGroups: Set<string>;
  insertMenu: InsertMenuState | null;
  loading: boolean;
  saving: boolean;
  checking: boolean;
  verifying: boolean;
  error: string | null;

  select(id: string | null): void;
  focusNode(id: string): void;
  /** 展开聚合链：成员立即从组当前位置垂直堆叠分配位置（几何稳定，避免 dagre 兜底甩到远处） */
  expandGroup(id: string, runIds: string[]): void;
  collapseGroup(id: string): void;
  setPosition(id: string, pos: Pos): void;
  openInsertMenu(menu: InsertMenuState | null): void;
  dismissVerify(): void;
  setError(message: string | null): void;
  undo(): void;
  redo(): void;
  /**
   * 全部编辑动作的唯一入口：fn 为 graph_ops 纯函数调用。
   * 返回新增节点 id 列表；fn 抛错（领域校验失败）时置 error 并返回 null。
   */
  mutateGraph(
    fn: (graph: BgalsGraph) => BgalsGraph,
    opts?: { tag?: string; selectNew?: boolean },
  ): string[] | null;
}

/** graph + positions 的持久化指纹（dirty 判定基准） */
export function snapshotOf(graph: BgalsGraph, positions: Map<string, Pos>): string {
  return JSON.stringify({ g: graph, p: [...positions.entries()].sort() });
}

/** diags 经 emit lineMap 映射到节点（line 落在节点行区间即归属；仅限当前剧本） */
export function mapDiags(
  graph: BgalsGraph,
  spec: BgalsSpec,
  report: CheckReport,
): { diagNode: (string | null)[]; nodeDiags: Record<string, DiagBadge> } {
  let lineMap: Record<string, { from: number; to: number }> = {};
  try {
    lineMap = emitGraph(graph, spec).lineMap;
  } catch {
    // 图暂不可发射（编辑中间态）：退化为不定位
  }
  const nodeDiags: Record<string, DiagBadge> = {};
  const diagNode = report.diags.map((d) => {
    if (scriptNameOfFile(d.file) !== graph.script) return null;
    const hit = Object.entries(lineMap).find(([, r]) => d.line >= r.from && d.line <= r.to);
    if (!hit) return null;
    const c = (nodeDiags[hit[0]] ??= { error: 0, warning: 0 });
    if (d.level === "error") c.error += 1;
    else c.warning += 1;
    return hit[0];
  });
  return { diagNode, nodeDiags };
}

export function errMsg(e: unknown): string {
  return (e as Error).message ?? String(e);
}

let lastTag: string | null = null;
let lastMutateAt = 0;

export const useEditor = create<EditorState>((set, get) => ({
  spec: null,
  refs: null,
  mode: "live",
  devMode: false,
  scripts: [],
  current: null,
  graph: null,
  positions: new Map(),
  selected: null,
  focusReq: null,
  report: null,
  diagNode: [],
  nodeDiags: {},
  verifyResult: null,
  dirty: false,
  lastSaved: null,
  undoStack: [],
  redoStack: [],
  expandedGroups: new Set<string>(),
  insertMenu: null,
  loading: false,
  saving: false,
  checking: false,
  verifying: false,
  error: null,

  select(id) {
    set({ selected: id });
  },
  focusNode(id) {
    set((s) => ({ selected: id, focusReq: { id, n: (s.focusReq?.n ?? 0) + 1 } }));
  },
  expandGroup(id, runIds) {
    const s = get();
    if (s.expandedGroups.has(id)) return;
    const next = new Set(s.expandedGroups);
    next.add(id);
    // 从组节点当前位置（拖动组时以 group:xxx 键写入）回退首节点位置，垂直堆叠
    const base =
      s.positions.get(id) ?? (runIds.length > 0 ? s.positions.get(runIds[0]) : undefined);
    if (base === undefined) {
      set({ expandedGroups: next });
      return;
    }
    const positions = new Map(s.positions);
    stackPositions(base, runIds.length).forEach((p, i) => positions.set(runIds[i], p));
    set({
      expandedGroups: next,
      positions,
      dirty: s.graph !== null && snapshotOf(s.graph, positions) !== s.lastSaved,
    });
  },
  collapseGroup(id) {
    const s = get();
    if (!s.expandedGroups.has(id)) return;
    const next = new Set(s.expandedGroups);
    next.delete(id);
    set({ expandedGroups: next });
  },
  setPosition(id, pos) {
    const s = get();
    if (!s.graph) return;
    const positions = new Map(s.positions);
    positions.set(id, pos);
    set({ positions, dirty: snapshotOf(s.graph, positions) !== s.lastSaved });
  },
  openInsertMenu(menu) {
    set({ insertMenu: menu });
  },
  dismissVerify() {
    set({ verifyResult: null });
  },
  setError(message) {
    set({ error: message });
  },

  undo() {
    const s = get();
    if (!s.graph || s.undoStack.length === 0) return;
    lastTag = null;
    const prev = s.undoStack[s.undoStack.length - 1];
    const redoStack = [...s.redoStack, structuredClone(s.graph)].slice(-UNDO_CAP);
    set({
      graph: prev,
      undoStack: s.undoStack.slice(0, -1),
      redoStack,
      dirty: snapshotOf(prev, s.positions) !== s.lastSaved,
      selected: prev.nodes.some((n) => n.id === s.selected) ? s.selected : null,
      nodeDiags: {},
      diagNode: s.report ? s.report.diags.map(() => null) : [],
    });
  },

  redo() {
    const s = get();
    if (!s.graph || s.redoStack.length === 0) return;
    lastTag = null;
    const next = s.redoStack[s.redoStack.length - 1];
    set({
      graph: next,
      redoStack: s.redoStack.slice(0, -1),
      undoStack: [...s.undoStack, structuredClone(s.graph)].slice(-UNDO_CAP),
      dirty: snapshotOf(next, s.positions) !== s.lastSaved,
      selected: next.nodes.some((n) => n.id === s.selected) ? s.selected : null,
      nodeDiags: {},
      diagNode: s.report ? s.report.diags.map(() => null) : [],
    });
  },

  mutateGraph(fn, opts = {}) {
    const s = get();
    if (!s.graph) return null;
    let next: BgalsGraph;
    try {
      next = fn(s.graph);
    } catch (e) {
      set({ error: errMsg(e) });
      return null;
    }
    const now = Date.now();
    const coalesce =
      opts.tag !== undefined && opts.tag === lastTag && now - lastMutateAt < COALESCE_MS;
    lastTag = opts.tag ?? null;
    lastMutateAt = now;

    const oldIds = new Set(s.graph.nodes.map((n) => n.id));
    const newIds = next.nodes.filter((n) => !oldIds.has(n.id)).map((n) => n.id);
    const positions = fillMissingPositions(next, new Map(s.positions));
    set({
      graph: next,
      positions,
      undoStack: coalesce
        ? s.undoStack
        : [...s.undoStack, structuredClone(s.graph)].slice(-UNDO_CAP),
      redoStack: coalesce ? s.redoStack : [],
      dirty: snapshotOf(next, positions) !== s.lastSaved,
      verifyResult: null,
      ...(opts.selectNew && newIds.length > 0 ? { selected: newIds[0] } : {}),
    });
    return newIds;
  },
}));
