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
import { useEffect, useMemo } from "react";
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

/** 节点是否已完成尺寸测量（fitView/setCenter 的正确性前提） */
function measured(n: { measured?: { width?: number; height?: number } }): boolean {
  return n.measured?.width !== undefined && n.measured?.height !== undefined;
}

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
  const { setCenter, getNode, getNodes, fitView } = useReactFlow();

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

  // 剧本载入/切换后可靠 fitView：rAF 轮询等全部节点测量完成（含 dagre 补位后的新位置）
  useEffect(() => {
    if (current === null) return;
    let alive = true;
    const tryFit = (attempt: number) => {
      if (!alive) return;
      const ns = getNodes();
      if (ns.length > 0 && ns.every(measured)) {
        void fitView({ padding: 0.2, duration: 250 });
        return;
      }
      if (attempt < 90) requestAnimationFrame(() => tryFit(attempt + 1));
    };
    const raf = requestAnimationFrame(() => tryFit(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [current, fitView, getNodes]);

  // 诊断定位 / select_node / 新节点滚入视野：rAF 重试等目标节点渲染并测量
  useEffect(() => {
    if (!focusReq) return;
    let alive = true;
    const tryCenter = (attempt: number) => {
      if (!alive) return;
      const n = getNode(focusReq.id);
      if (n && measured(n)) {
        const w = n.measured?.width ?? 240;
        const h = n.measured?.height ?? 100;
        void setCenter(n.position.x + w / 2, n.position.y + h / 2, { zoom: 1.1, duration: 300 });
        return;
      }
      if (attempt < 90) requestAnimationFrame(() => tryCenter(attempt + 1));
    };
    const raf = requestAnimationFrame(() => tryCenter(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [focusReq, getNode, setCenter]);

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
          if (node.type === "group") expandGroup(node.id);
        }}
        defaultEdgeOptions={defaultEdgeOptions}
        fitViewOptions={{ padding: 0.2 }}
        colorMode="dark"
        zoomOnDoubleClick={false}
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
