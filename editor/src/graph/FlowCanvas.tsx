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
import { useEffect, useMemo, useRef } from "react";
import { flowNeighbor } from "../../shared/graph_walk";
import { removeNodeById } from "../state/edit";
import { useEditor } from "../state/store";
import { collapseRuns, groupIdOf, isGroupNode } from "./collapse";
import { SeqEdge } from "./edges/SeqEdge";
import { kindColor } from "./kindColor";
import { CommentNode } from "./nodes/CommentNode";
import { CondNode } from "./nodes/CondNode";
import { DialogueNode } from "./nodes/DialogueNode";
import { InstNode } from "./nodes/InstNode";
import { JumpNode } from "./nodes/JumpNode";
import { OptionGroupNode } from "./nodes/OptionGroupNode";
import { RunGroupNode } from "./nodes/RunGroupNode";
import { EndNode, StartNode } from "./nodes/StartEndNode";
import { toFlow, type FlowData, type FlowNode } from "./toFlow";

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

function Canvas() {
  const graph = useEditor((s) => s.graph);
  const positions = useEditor((s) => s.positions);
  const nodeDiags = useEditor((s) => s.nodeDiags);
  const selected = useEditor((s) => s.selected);
  const current = useEditor((s) => s.current);
  const select = useEditor((s) => s.select);
  const setPosition = useEditor((s) => s.setPosition);
  const focusReq = useEditor((s) => s.focusReq);
  const expandedGroups = useEditor((s) => s.expandedGroups);
  const expandGroup = useEditor((s) => s.expandGroup);
  const { setCenter, getNode, getNodes, fitView, getZoom } = useReactFlow();

  // 领域图 → 聚合视图 → toFlow；带诊断角标/当前选中的节点强制可见
  const { nodes, edges } = useMemo(() => {
    if (!graph) return { nodes: [], edges: [] };
    const forced = new Set([...Object.keys(nodeDiags), ...(selected ? [selected] : [])]);
    const view = collapseRuns(graph, expandedGroups, forced);
    const flow = toFlow(view, positions, nodeDiags, graph.edges);
    // 展开中链的首节点给「收起」按钮
    const expandedHeads = new Set([...expandedGroups].map((id) => id.slice(groupIdOf("").length)));
    return {
      nodes: flow.nodes.map((n) =>
        expandedHeads.has(n.id) ? { ...n, data: { ...n.data, collapseId: groupIdOf(n.id) } } : n,
      ),
      edges: flow.edges,
    };
  }, [graph, positions, nodeDiags, selected, expandedGroups]);

  const rendered = useMemo(
    () => nodes.map((n) => ({ ...n, selected: n.id === selected })),
    [nodes, selected],
  );

  // 剧本载入/切换后的视口策略：全图能按可读缩放放下才 fitView，否则聚焦起点按阅读缩放展示。
  // 就绪判定以 DOM 实际渲染为准（RF 内部 measured 无可靠 effect 触发源），rAF 轮询，每剧本一次。
  const fittedFor = useRef<string | null>(null);
  useEffect(() => {
    fittedFor.current = null;
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

  // 受控模式：change 事件回流到领域 store（位置独立存放；remove 走 removeNode）
  const onNodesChange = (changes: NodeChange<FlowNode>[]) => {
    for (const ch of changes) {
      if (ch.type === "position" && ch.position) {
        setPosition(ch.id, ch.position);
      } else if (ch.type === "select") {
        if (ch.selected) select(ch.id);
        else if (useEditor.getState().selected === ch.id) select(null);
      } else if (ch.type === "remove") {
        const node = graph?.nodes.find((n) => n.id === ch.id);
        if (node && node.kind !== "start" && node.kind !== "end") removeNodeById(ch.id);
      }
    }
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
        onNodeClick={(_, node) => {
          const d = node.data as FlowData;
          if (isGroupNode(d.node)) expandGroup(d.node.id, d.node.runIds);
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
            const d = n.data as FlowData | undefined;
            const key = d && isGroupNode(d.node) ? d.node.groupKind : (n.type ?? "");
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
