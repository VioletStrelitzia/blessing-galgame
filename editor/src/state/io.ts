// IO 动作：初始化、剧本载入（graph + sidecar 并行，404 容忍）、保存流、检查、回环校验。
// 均为操作 store 的普通函数（组件直接 import 调用；响应式状态经 useEditor 订阅）。

import { semanticEqual } from "../../shared/compare";
import { emitGraph } from "../../shared/emit";
import type { BgalsGraph } from "../../shared/graph";
import { applySidecar, buildSidecar } from "../../shared/sidecar";
import { api } from "../api";
import { collapseRuns, viewPositionsOf } from "../graph/collapse";
import { fillMissingPositions, type Pos } from "../graph/layout";
import { errMsg, mapDiags, snapshotOf, useEditor } from "./store";

export async function init(): Promise<void> {
  const s = useEditor.getState();
  if (s.loading || s.spec !== null) return;
  useEditor.setState({ loading: true, error: null });
  try {
    const [spec, refs, mode, graphs] = await Promise.all([
      api.spec(),
      api.refs(),
      api.mode(),
      api.graphs(),
    ]);
    useEditor.setState({
      spec,
      refs,
      mode: mode.mode,
      devMode: mode.dev,
      scripts: graphs.map((g) => g.script),
      loading: false,
    });
    const first = graphs[0];
    if (first) await openScript(first.script);
  } catch (e) {
    useEditor.setState({ error: errMsg(e), loading: false });
  }
}

export async function openScript(script: string): Promise<void> {
  useEditor.setState({ loading: true, error: null });
  try {
    const [graph, sidecar] = await Promise.all([api.graph(script), api.sidecar(script)]);
    let g: BgalsGraph = graph;
    let positions = new Map<string, Pos>();
    if (sidecar !== null) {
      const applied = applySidecar(graph, sidecar);
      g = { ...graph, nodes: [...graph.nodes, ...applied.comments] };
      positions = applied.positions;
    }
    // 布局作用于聚合后的视图图（初始全折叠）：组只占一格，成员槽位不推高下游节点
    const view = collapseRuns(g, new Set());
    positions = fillMissingPositions(view, viewPositionsOf(view, positions));
    useEditor.setState({
      graph: g,
      current: script,
      positions,
      selected: null,
      focusReq: null,
      undoStack: [],
      redoStack: [],
      expandedGroups: new Set(),
      lastSaved: snapshotOf(g, positions),
      dirty: false,
      report: null,
      diagNode: [],
      nodeDiags: {},
      verifyResult: null,
      insertMenu: null,
      loading: false,
    });
  } catch (e) {
    useEditor.setState({ error: errMsg(e), loading: false });
  }
}

export async function newScript(name: string): Promise<void> {
  const { mode } = useEditor.getState();
  if (mode === "fixtures") {
    useEditor.setState({ error: "fixtures 模式为只读，不支持新建剧本" });
    return;
  }
  try {
    await api.createScript(name);
    useEditor.setState((s) => ({ scripts: [...s.scripts, name].sort() }));
    await openScript(name);
  } catch (e) {
    useEditor.setState({ error: errMsg(e) });
  }
}

export async function runCheck(): Promise<void> {
  useEditor.setState({ checking: true, error: null });
  try {
    const report = await api.check();
    const { graph, spec } = useEditor.getState();
    const mapped = graph && spec ? mapDiags(graph, spec, report) : { diagNode: [], nodeDiags: {} };
    useEditor.setState({ report, ...mapped, checking: false });
  } catch (e) {
    useEditor.setState({ checking: false, error: errMsg(e) });
  }
}

/** 保存流：emitGraph → POST save（text + sidecar）→ 成功后自动 check 并重映射诊断 */
export async function save(): Promise<void> {
  const { graph, spec, current, positions } = useEditor.getState();
  if (!graph || !spec || !current) return;
  useEditor.setState({ saving: true, error: null });
  try {
    const { text } = emitGraph(graph, spec);
    const sidecar = buildSidecar(graph, positions, graph.compiler, current);
    await api.save(current, text, sidecar);
    useEditor.setState({ lastSaved: snapshotOf(graph, positions), dirty: false, saving: false });
    await runCheck();
  } catch (e) {
    useEditor.setState({ saving: false, error: errMsg(e) });
  }
}

/** 回环校验：重新 dump 服务端图（live 模式先增量编译保鲜），与内存图做语义对比 */
export async function verify(): Promise<void> {
  const { graph, current, mode } = useEditor.getState();
  if (!graph || !current) return;
  if (mode === "fixtures") {
    useEditor.setState({ error: "fixtures 模式无引擎可回读，回环校验不可用" });
    return;
  }
  useEditor.setState({ verifying: true, error: null });
  try {
    const fresh = await api.graph(current);
    const result = semanticEqual(graph, fresh);
    useEditor.setState({ verifyResult: { ...result, at: Date.now() }, verifying: false });
  } catch (e) {
    useEditor.setState({ verifying: false, error: errMsg(e) });
  }
}
