// 编辑器领域状态（zustand）：图是唯一事实源，React Flow 仅为视图投影。
// 所有图变更经 mutateGraph（调 graph_ops 纯函数 → 压撤销快照 cap 100 → 置 dirty）。
// 撤销快照 = 图 + 位置（sidecar 布局可撤销）；拖动位置经 beginMove/endMove 合并为一个撤销步；
// settle 防重叠等视图机制的位置写入（setPositions）不进撤销栈，载入后首次自动规整不标 dirty。
// IO 动作（init/openScript/save/check/verify）见 state/io.ts，编辑动作见 state/edit.ts。

import { create } from "zustand";
import { scriptNameOfFile, type CheckReport } from "../../shared/check";
import { emitGraph } from "../../shared/emit";
import type { BgalsGraph } from "../../shared/graph";
import type { BgalsOverview } from "../../shared/overview";
import type { BgalsSpec } from "../../shared/spec";
import type { ModeInfo, RefsData } from "../api";
import { EXPAND_GAP_Y, stackPositions } from "../graph/collapse";
import { estimateSizeFor, fillMissingPositions, type Pos } from "../graph/layout";
import type { DiagBadge } from "../graph/toFlow";

export type { Pos };

export const UNDO_CAP = 100;
/** 相同 tag 的连续变更（如逐键输入）在该窗口内合并为一个撤销步 */
const COALESCE_MS = 800;

/** 撤销快照：图 + 位置（sidecar 布局同样可撤销） */
export interface Snapshot {
  g: BgalsGraph;
  p: Map<string, Pos>;
}

function snapOf(graph: BgalsGraph, positions: Map<string, Pos>): Snapshot {
  return { g: structuredClone(graph), p: new Map(positions) };
}

function samePositions(a: Map<string, Pos>, b: Map<string, Pos>): boolean {
  if (a.size !== b.size) return false;
  for (const [k, p] of a) {
    const q = b.get(k);
    if (!q || q.x !== p.x || q.y !== p.y) return false;
  }
  return true;
}

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
  /** detail = 剧本画布；overview = 剧本宏观关系总览 */
  view: "detail" | "overview";
  overview: BgalsOverview | null;
  overviewLoading: boolean;
  /** 总览画布中选中的剧本节点 id（剧本名） */
  overviewSelected: string | null;
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
  undoStack: Snapshot[];
  redoStack: Snapshot[];
  /** 拖动等连续手势的起始位置快照（beginMove 暂存 / endMove 压栈；非 null 期间 setPosition 不压栈） */
  pendingSnap: Map<string, Pos> | null;
  /** 已展开的聚合链（group:<首节点 id> 集合，视图层状态，随剧本切换清空） */
  expandedGroups: Set<string>;
  /** 展开时的下游腾挪记录（收起时反向收回，防反复展开/收起的布局漂移；视图层，随剧本切换清空） */
  expandShift: Map<string, { delta: number; baseY: number; memberIds: Set<string> }>;
  insertMenu: InsertMenuState | null;
  loading: boolean;
  saving: boolean;
  checking: boolean;
  verifying: boolean;
  error: string | null;

  select(id: string | null): void;
  focusNode(id: string): void;
  selectOverviewNode(id: string | null): void;
  /** 展开聚合链：成员立即从组当前位置垂直堆叠分配位置（几何稳定，避免 dagre 兜底甩到远处） */
  expandGroup(id: string, runIds: string[]): void;
  collapseGroup(id: string): void;
  setPosition(id: string, pos: Pos): void;
  /**
   * 批量写位置（settle 防重叠等视图机制用）：不进撤销栈。
   * normalize=true 且当前无用户改动时，视为载入后自动规整：位置落盘基线随动，不标 dirty。
   */
  setPositions(next: Map<string, Pos>, opts?: { normalize?: boolean }): void;
  /** 拖动手势开始：暂存位置快照（手势期间 setPosition 不压撤销栈） */
  beginMove(): void;
  /** 拖动手势结束：位置确有变化则把手势前快照压入撤销栈（整段拖动 = 一个撤销步） */
  endMove(): void;
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
  view: "detail",
  overview: null,
  overviewLoading: false,
  overviewSelected: null,
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
  pendingSnap: null,
  expandedGroups: new Set<string>(),
  expandShift: new Map(),
  insertMenu: null,
  loading: false,
  saving: false,
  checking: false,
  verifying: false,
  error: null,

  select(id) {
    set({ selected: id });
  },
  selectOverviewNode(id) {
    set({ overviewSelected: id });
  },
  focusNode(id) {
    set((s) => ({ selected: id, focusReq: { id, n: (s.focusReq?.n ?? 0) + 1 } }));
  },
  expandGroup(id, runIds) {
    const s = get();
    if (s.expandedGroups.has(id)) return;
    const next = new Set(s.expandedGroups);
    next.add(id);
    // 从组节点当前位置（拖动组时以 group:xxx 键写入）回退首节点位置；
    // 按成员估算高度堆叠，与真实渲染高度的残差由 FlowCanvas settle 按实测修正
    const base =
      s.positions.get(id) ?? (runIds.length > 0 ? s.positions.get(runIds[0]) : undefined);
    if (base === undefined) {
      set({ expandedGroups: next });
      return;
    }
    const heights = runIds.map((rid) => {
      const n = s.graph?.nodes.find((nd) => nd.id === rid);
      return n ? estimateSizeFor(n.kind).height : 60;
    });
    const positions = new Map(s.positions);
    stackPositions(base, heights).forEach((p, i) => positions.set(runIds[i], p));
    // 下游腾挪：组原只占一格，展开需要整链高度——把所有位于组下方的节点垂直下移出空间，
    // 保持流式阅读顺序（否则下游节点会被链成员夹击在分组框内）。收起时按记录反向收回。
    const runHeight = heights.reduce((a, b) => a + b, 0) + EXPAND_GAP_Y * (runIds.length - 1);
    const delta = runHeight + EXPAND_GAP_Y - estimateSizeFor("group").height;
    const expandShift = new Map(s.expandShift);
    if (delta > 0) {
      const memberIds = new Set(runIds);
      for (const [pid, p] of [...positions.entries()]) {
        if (memberIds.has(pid)) continue;
        if (p.y > base.y + 1) positions.set(pid, { x: p.x, y: p.y + delta });
      }
      expandShift.set(id, { delta, baseY: base.y, memberIds });
    } else {
      expandShift.delete(id);
    }
    set({
      expandedGroups: next,
      positions,
      expandShift,
      dirty: s.graph !== null && snapshotOf(s.graph, positions) !== s.lastSaved,
    });
  },
  collapseGroup(id) {
    const s = get();
    if (!s.expandedGroups.has(id)) return;
    const next = new Set(s.expandedGroups);
    next.delete(id);
    const rec = s.expandShift.get(id);
    if (!rec || !s.graph) {
      set({ expandedGroups: next });
      return;
    }
    // 反向收回展开时的下游腾挪（成员位置保留，组收起后成员离开视图）
    const expandShift = new Map(s.expandShift);
    expandShift.delete(id);
    const positions = new Map(s.positions);
    for (const [pid, p] of [...positions.entries()]) {
      if (rec.memberIds.has(pid)) continue;
      if (p.y > rec.baseY + 1) positions.set(pid, { x: p.x, y: p.y - rec.delta });
    }
    set({
      expandedGroups: next,
      expandShift,
      positions,
      dirty: snapshotOf(s.graph, positions) !== s.lastSaved,
    });
  },
  setPosition(id, pos) {
    const s = get();
    if (!s.graph) return;
    const positions = new Map(s.positions);
    positions.set(id, pos);
    set({ positions, dirty: snapshotOf(s.graph, positions) !== s.lastSaved });
  },
  setPositions(next, opts) {
    const s = get();
    if (!s.graph) return;
    const normalize = opts?.normalize === true && !s.dirty;
    set({
      positions: next,
      dirty: normalize ? false : snapshotOf(s.graph, next) !== s.lastSaved,
      ...(normalize ? { lastSaved: snapshotOf(s.graph, next) } : {}),
    });
  },
  beginMove() {
    const s = get();
    if (s.pendingSnap !== null || !s.graph) return;
    set({ pendingSnap: new Map(s.positions) });
  },
  endMove() {
    const s = get();
    if (s.pendingSnap === null || !s.graph) return;
    const before = s.pendingSnap;
    const changed = !samePositions(before, s.positions);
    set({
      pendingSnap: null,
      ...(changed
        ? {
            undoStack: [...s.undoStack, { g: structuredClone(s.graph), p: before }].slice(
              -UNDO_CAP,
            ),
            redoStack: [],
          }
        : {}),
    });
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
    const redoStack = [...s.redoStack, snapOf(s.graph, s.positions)].slice(-UNDO_CAP);
    set({
      graph: prev.g,
      positions: prev.p,
      undoStack: s.undoStack.slice(0, -1),
      redoStack,
      pendingSnap: null,
      dirty: snapshotOf(prev.g, prev.p) !== s.lastSaved,
      selected: prev.g.nodes.some((n) => n.id === s.selected) ? s.selected : null,
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
      graph: next.g,
      positions: next.p,
      redoStack: s.redoStack.slice(0, -1),
      undoStack: [...s.undoStack, snapOf(s.graph, s.positions)].slice(-UNDO_CAP),
      pendingSnap: null,
      dirty: snapshotOf(next.g, next.p) !== s.lastSaved,
      selected: next.g.nodes.some((n) => n.id === s.selected) ? s.selected : null,
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
        : [...s.undoStack, snapOf(s.graph, s.positions)].slice(-UNDO_CAP),
      redoStack: coalesce ? s.redoStack : [],
      pendingSnap: null, // 图变更打断进行中的拖动手势（理论上不会并存，防御）
      dirty: snapshotOf(next, positions) !== s.lastSaved,
      verifyResult: null,
      ...(opts.selectNew && newIds.length > 0 ? { selected: newIds[0] } : {}),
    });
    return newIds;
  },
}));
