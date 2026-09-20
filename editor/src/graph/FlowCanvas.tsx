import {
  Controls,
  MarkerType,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type EdgeTypes,
  type NodeChange,
  type NodeTypes,
} from "@xyflow/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { flowNeighbor } from "../../shared/graph_walk";
import { removeNodeById } from "../state/edit";
import { useEditor } from "../state/store";
import { separateOverlaps, type CollideRect } from "./collide";
import { collapseRuns, findRuns, groupIdOf, isGroupNode, viewPositionsOf } from "./collapse";
import { SeqEdge } from "./edges/SeqEdge";
import { frameRects } from "./frames";
import { kindColor } from "./kindColor";
import { fillMissingPositions } from "./layout";
import { CommentNode } from "./nodes/CommentNode";
import { CondNode } from "./nodes/CondNode";
import { DialogueNode } from "./nodes/DialogueNode";
import { InstNode } from "./nodes/InstNode";
import { JumpNode } from "./nodes/JumpNode";
import { OptionGroupNode } from "./nodes/OptionGroupNode";
import { RunGroupNode } from "./nodes/RunGroupNode";
import { EndNode, StartNode } from "./nodes/StartEndNode";
import { FrameNode } from "./nodes/FrameNode";
import { toFlow, type AnyFlowNode, type FlowData } from "./toFlow";

const nodeTypes: NodeTypes = {
  start: StartNode,
  end: EndNode,
  dialogue: DialogueNode,
  inst: InstNode,
  option_group: OptionGroupNode,
  cond: CondNode,
  jump: JumpNode,
  comment: CommentNode,
  group: RunGroupNode,
  frame: FrameNode,
};

const edgeTypes: EdgeTypes = { seq: SeqEdge };

const defaultEdgeOptions = {
  type: "smoothstep",
  markerEnd: { type: MarkerType.ArrowClosed, width: 14, height: 14, color: "#64748B" },
} as const;

// 视口策略常量：全图 fit 的可读下限、长图载入时的阅读缩放、手动缩放下限
const LOAD_FIT_MIN = 0.75;
const READ_ZOOM = 0.85;
const MIN_ZOOM = 0.3;

/** settle 写回护栏：连续 N 轮仍未收敛即停手（理论不可达，防非收敛死循环） */
const SETTLE_GUARD = 30;

type SizeMap = Map<string, { w: number; h: number }>;

function sameSizeMap(a: SizeMap, b: SizeMap): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) {
    const u = b.get(k);
    if (!u || Math.abs(u.w - v.w) > 0.5 || Math.abs(u.h - v.h) > 0.5) return false;
  }
  return true;
}

/** 量取当前全部可见节点（frame 除外）的实测尺寸（屏幕 px ÷ zoom → 流程坐标） */
function measureNodes(zoom: number): SizeMap {
  const m: SizeMap = new Map();
  document.querySelectorAll(".react-flow__node[data-id]").forEach((el) => {
    const id = el.getAttribute("data-id");
    if (id === null || id.startsWith("frame:")) return;
    const r = el.getBoundingClientRect();
    if (r.width > 0) m.set(id, { w: r.width / zoom, h: r.height / zoom });
  });
  return m;
}

function Canvas() {
  const graph = useEditor((s) => s.graph);
  const positions = useEditor((s) => s.positions);
  const nodeDiags = useEditor((s) => s.nodeDiags);
  const selected = useEditor((s) => s.selected);
  const current = useEditor((s) => s.current);
  const select = useEditor((s) => s.select);
  const setPosition = useEditor((s) => s.setPosition);
  const setPositions = useEditor((s) => s.setPositions);
  const beginMove = useEditor((s) => s.beginMove);
  const endMove = useEditor((s) => s.endMove);
  const focusReq = useEditor((s) => s.focusReq);
  const expandedGroups = useEditor((s) => s.expandedGroups);
  const expandGroup = useEditor((s) => s.expandGroup);
  const { setCenter, getNode, getNodes, fitView, getZoom } = useReactFlow();

  // 实测尺寸（settle pass 量取）：frame 包围盒按真实高度收边，拖动碰撞复用
  const [sizes, setSizes] = useState<SizeMap>(new Map());
  // 拖动手势状态：碰撞推挤在 onNodesChange 里实时做，settle pass 期间挂起
  const draggingRef = useRef(false);
  const dragSizesRef = useRef<SizeMap | null>(null);
  // settle 签名（同状态不重复跑）与收敛护栏；载入后首次 settle 为自动规整（不标 dirty）
  const settleSigRef = useRef("");
  const settleGuardRef = useRef(0);
  const settleNormFor = useRef<string | null>(null);

  // 领域图 → 聚合视图 → 视图图布局（fillMissingPositions/dagre 作用于视图节点，
  // 被折叠成员不占槽位，组只占一格，杜绝跨空槽的超长边）→ toFlow；带诊断角标/当前选中的节点强制可见
  const { nodes, edges } = useMemo(() => {
    if (!graph) return { nodes: [] as AnyFlowNode[], edges: [] };
    const forced = new Set([...Object.keys(nodeDiags), ...(selected ? [selected] : [])]);
    const view = collapseRuns(graph, expandedGroups, forced);
    const laid = fillMissingPositions(view, viewPositionsOf(view, positions));
    const flow = toFlow(view, laid, nodeDiags, graph.edges);
    // 展开中链的首节点给「收起」按钮
    const expandedHeads = new Set([...expandedGroups].map((id) => id.slice(groupIdOf("").length)));
    const flowNodes: AnyFlowNode[] = flow.nodes.map((n) =>
      expandedHeads.has(n.id) ? { ...n, data: { ...n.data, collapseId: groupIdOf(n.id) } } : n,
    );
    // 展开中的链外套 Archify 分组框（压底、点击穿透、位置随成员拖动重算；尺寸用实测）
    const frames: AnyFlowNode[] = frameRects(
      findRuns(graph, forced),
      expandedGroups,
      laid,
      sizes,
    ).map((f) => ({
      id: `frame:${f.groupId}`,
      type: "frame" as const,
      position: { x: f.x, y: f.y },
      data: { frame: { label: f.label, color: kindColor(f.groupKind) } },
      selectable: false,
      draggable: false,
      focusable: false,
      zIndex: -1,
      style: { width: f.width, height: f.height, zIndex: -1, pointerEvents: "none" },
    }));
    return { nodes: [...frames, ...flowNodes], edges: flow.edges };
  }, [graph, positions, nodeDiags, selected, expandedGroups, sizes]);

  const rendered = useMemo(
    () => nodes.map((n) => ({ ...n, selected: n.id === selected })),
    [nodes, selected],
  );

  // 剧本载入/切换后的视口策略：全图能按可读缩放放下才 fitView，否则聚焦起点按阅读缩放展示。
  // 就绪判定以 DOM 实际渲染为准（RF 内部 measured 无可靠 effect 触发源），rAF 轮询，每剧本一次。
  const fittedFor = useRef<string | null>(null);
  useEffect(() => {
    fittedFor.current = null;
    settleSigRef.current = "";
    settleGuardRef.current = 0;
    settleNormFor.current = null;
  }, [current]);
  useEffect(() => {
    if (current === null || fittedFor.current === current || nodes.length === 0) return;
    let alive = true;
    const tryFit = (attempt: number) => {
      if (!alive || fittedFor.current === current) return;
      const dom = document.querySelectorAll(".react-flow__node");
      const ready =
        dom.length >= nodes.length && [...dom].every((el) => el.getBoundingClientRect().width > 0);
      if (!ready) {
        if (attempt < 1200) requestAnimationFrame(() => tryFit(attempt + 1));
        return;
      }
      fittedFor.current = current;
      const ns = getNodes();
      const x0 = Math.min(...ns.map((n) => n.position.x));
      const y0 = Math.min(...ns.map((n) => n.position.y));
      const x1 = Math.max(...ns.map((n) => n.position.x + (n.measured?.width ?? 240)));
      const y1 = Math.max(...ns.map((n) => n.position.y + (n.measured?.height ?? 100)));
      const pane = document.querySelector(".react-flow__pane")?.getBoundingClientRect();
      const fitZoom = Math.min(
        ((pane?.width ?? 1200) * 0.8) / Math.max(x1 - x0, 1),
        ((pane?.height ?? 800) * 0.8) / Math.max(y1 - y0, 1),
      );
      if (fitZoom >= LOAD_FIT_MIN) {
        void fitView({ padding: 0.2, minZoom: MIN_ZOOM, duration: 250 });
      } else {
        const start = ns.find((n) => n.type === "start") ?? ns[0];
        void setCenter(start.position.x + 120, start.position.y + 180, {
          zoom: READ_ZOOM,
          duration: 250,
        });
      }
    };
    const raf = requestAnimationFrame(() => tryFit(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [current, nodes, fitView, getNodes, setCenter]);

  // 防重叠 settle：渲染稳定后按实测尺寸跑 separateOverlaps，把重叠节点推开（写回 positions）。
  // 触发面：载入规整（估算补位的残差）、展开聚合、文本编辑致节点变高。拖动期间挂起
  // （拖动碰撞在 onNodesChange 实时处理）。签名去重 + 收敛护栏保证不自激。
  useEffect(() => {
    if (nodes.length === 0) return;
    let alive = true;
    const trySettle = (attempt: number) => {
      if (!alive || draggingRef.current) return;
      const zoom = getZoom() || 1;
      const rects: CollideRect[] = [];
      const nextSizes: SizeMap = new Map();
      for (const n of nodes) {
        if (n.type === "frame") continue;
        const el = document.querySelector(`.react-flow__node[data-id="${CSS.escape(n.id)}"]`);
        const r = el?.getBoundingClientRect();
        if (!r || r.width === 0) {
          if (attempt < 600) requestAnimationFrame(() => trySettle(attempt + 1));
          return;
        }
        rects.push({
          id: n.id,
          x: n.position.x,
          y: n.position.y,
          w: r.width / zoom,
          h: r.height / zoom,
        });
        nextSizes.set(n.id, { w: r.width / zoom, h: r.height / zoom });
      }
      setSizes((prev) => (sameSizeMap(prev, nextSizes) ? prev : nextSizes));
      const sig = rects
        .map(
          (r) =>
            `${r.id}:${Math.round(r.x)}:${Math.round(r.y)}:${Math.round(r.w)}:${Math.round(r.h)}`,
        )
        .join("|");
      if (sig === settleSigRef.current) return;
      settleSigRef.current = sig;
      const moved = separateOverlaps(rects);
      if (moved.size === 0) {
        settleGuardRef.current = 0; // 健康态：护栏归零
        return;
      }
      if (settleGuardRef.current > SETTLE_GUARD) return;
      settleGuardRef.current += 1;
      const s = useEditor.getState();
      const np = new Map(s.positions);
      for (const [id, p] of moved) np.set(id, p);
      setPositions(np, { normalize: settleNormFor.current !== s.current });
      settleNormFor.current = s.current;
    };
    const raf = requestAnimationFrame(() => trySettle(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [nodes, getZoom, setPositions]);

  // 诊断定位 / select_node / 新节点滚入视野：同样以 DOM 渲染就绪为准（measured 无可靠触发源）
  useEffect(() => {
    if (!focusReq) return;
    let alive = true;
    const tryCenter = (attempt: number) => {
      if (!alive) return;
      const n = getNode(focusReq.id);
      const el = document.querySelector(`.react-flow__node[data-id="${CSS.escape(focusReq.id)}"]`);
      if (n && el && el.getBoundingClientRect().width > 0) {
        const zoom = getZoom() || 1;
        const rect = el.getBoundingClientRect();
        void setCenter(
          n.position.x + rect.width / zoom / 2,
          n.position.y + rect.height / zoom / 2,
          {
            zoom: READ_ZOOM,
            duration: 300,
          },
        );
        return;
      }
      if (attempt < 600) requestAnimationFrame(() => tryCenter(attempt + 1));
    };
    const raf = requestAnimationFrame(() => tryCenter(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [focusReq, getNode, setCenter, getZoom]);

  // 方向键上下游导航：ArrowDown=下一个 / ArrowUp=上一个（focusReq 居中；折叠内节点经 forcedVisible 显形）
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
      const target = e.target as HTMLElement | null;
      if (
        target !== null &&
        (/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable)
      ) {
        return;
      }
      const s = useEditor.getState();
      if (!s.graph || s.selected === null) return;
      const next = flowNeighbor(s.graph, s.selected, e.key === "ArrowDown" ? 1 : -1);
      if (next === null) return;
      e.preventDefault();
      s.focusNode(next);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // 受控模式：change 事件回流到领域 store（位置独立存放；remove 走 removeNode）。
  // 拖动中的位置变更附带实时碰撞推挤：被拖节点钉住，其余节点按实测尺寸让位（物理碰撞手感）。
  const onNodesChange = (changes: NodeChange<AnyFlowNode>[]) => {
    const dragged: string[] = [];
    for (const ch of changes) {
      if (ch.type === "position" && ch.position) {
        setPosition(ch.id, ch.position);
        if (ch.dragging) dragged.push(ch.id);
      } else if (ch.type === "select") {
        if (ch.selected) select(ch.id);
        else if (useEditor.getState().selected === ch.id) select(null);
      } else if (ch.type === "remove") {
        const node = graph?.nodes.find((n) => n.id === ch.id);
        if (node && node.kind !== "start" && node.kind !== "end") removeNodeById(ch.id);
      }
    }
    if (dragged.length === 0 || dragSizesRef.current === null) return;
    const sz = dragSizesRef.current;
    const latest = useEditor.getState().positions;
    const rects: CollideRect[] = [];
    for (const n of nodes) {
      if (n.type === "frame") continue;
      const size = sz.get(n.id);
      if (!size) continue;
      const p = latest.get(n.id) ?? n.position;
      rects.push({ id: n.id, x: p.x, y: p.y, w: size.w, h: size.h });
    }
    const moved = separateOverlaps(rects, { pinned: new Set(dragged) });
    if (moved.size === 0) return;
    const np = new Map(latest);
    for (const [id, p] of moved) np.set(id, p);
    setPositions(np);
  };

  // 拖动手势边界：开始量取全部节点尺寸（拖动中尺寸不变）+ 暂存撤销快照；结束收尾
  const onNodeDragStart = () => {
    draggingRef.current = true;
    dragSizesRef.current = measureNodes(getZoom() || 1);
    beginMove();
  };
  const onNodeDragStop = () => {
    draggingRef.current = false;
    dragSizesRef.current = null;
    endMove();
  };

  if (!graph) {
    return (
      <div className="flow-dots flex h-full items-center justify-center text-sm text-dim">
        加载中…
      </div>
    );
  }

  return (
    <div className="flow-dots h-full">
      <ReactFlow
        nodes={rendered}
        edges={edges}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodesChange={onNodesChange}
        onNodeDragStart={onNodeDragStart}
        onNodeDragStop={onNodeDragStop}
        onNodeClick={(_, node) => {
          const d = node.data as FlowData;
          if (d.node && isGroupNode(d.node)) expandGroup(d.node.id, d.node.runIds);
        }}
        defaultEdgeOptions={defaultEdgeOptions}
        fitViewOptions={{ padding: 0.2, minZoom: MIN_ZOOM }}
        colorMode="dark"
        zoomOnDoubleClick={false}
        nodeClickDistance={10}
        minZoom={MIN_ZOOM}
        nodesConnectable={false}
        edgesFocusable={false}
        deleteKeyCode={["Delete", "Backspace"]}
        onPaneClick={() => select(null)}
      >
        <Controls showInteractive={false} />
        <MiniMap
          pannable
          zoomable
          nodeColor={(n) => {
            if (n.type === "frame") return "transparent";
            const d = n.data as FlowData | undefined;
            const key = d && d.node && isGroupNode(d.node) ? d.node.groupKind : (n.type ?? "");
            return kindColor(key);
          }}
          nodeStrokeColor={() => "transparent"}
          maskColor="rgba(2, 6, 23, 0.75)"
        />
      </ReactFlow>
    </div>
  );
}

export function FlowCanvas() {
  return (
    <ReactFlowProvider>
      <Canvas />
    </ReactFlowProvider>
  );
}
