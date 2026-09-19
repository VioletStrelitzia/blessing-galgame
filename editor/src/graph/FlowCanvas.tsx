import {
  Controls,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type EdgeTypes,
  type NodeChange,
  type NodeTypes,
} from "@xyflow/react";
import { useEffect, useMemo, useRef } from "react";
import { removeNodeById } from "../state/edit";
import { useEditor } from "../state/store";
import { SeqEdge } from "./edges/SeqEdge";
import { CommentNode } from "./nodes/CommentNode";
import { CondNode } from "./nodes/CondNode";
import { DialogueNode } from "./nodes/DialogueNode";
import { InstNode } from "./nodes/InstNode";
import { JumpNode } from "./nodes/JumpNode";
import { OptionGroupNode } from "./nodes/OptionGroupNode";
import { EndNode, StartNode } from "./nodes/StartEndNode";
import { toFlow, type FlowNode } from "./toFlow";

const nodeTypes: NodeTypes = {
  start: StartNode,
  end: EndNode,
  dialogue: DialogueNode,
  inst: InstNode,
  option_group: OptionGroupNode,
  cond: CondNode,
  jump: JumpNode,
  comment: CommentNode,
};

const edgeTypes: EdgeTypes = { seq: SeqEdge };

const MINIMAP_COLORS: Record<string, string> = {
  start: "#e4e4e7",
  end: "#e4e4e7",
  dialogue: "#22d3ee",
  inst: "#818cf8",
  option_group: "#fbbf24",
  cond: "#fbbf24",
  jump: "#f87171",
  comment: "#71717a",
};

function Canvas() {
  const graph = useEditor((s) => s.graph);
  const positions = useEditor((s) => s.positions);
  const nodeDiags = useEditor((s) => s.nodeDiags);
  const selected = useEditor((s) => s.selected);
  const current = useEditor((s) => s.current);
  const select = useEditor((s) => s.select);
  const setPosition = useEditor((s) => s.setPosition);
  const focusReq = useEditor((s) => s.focusReq);
  const { setCenter, getNode, fitView, getZoom } = useReactFlow();

  const { nodes, edges } = useMemo(() => {
    if (!graph) return { nodes: [], edges: [] };
    return toFlow(graph, positions, nodeDiags);
  }, [graph, positions, nodeDiags]);

  const rendered = useMemo(
    () => nodes.map((n) => ({ ...n, selected: n.id === selected })),
    [nodes, selected],
  );

  // 剧本载入/切换后可靠 fitView：图数据可能晚于 current 变更到达（live 模式需等编译+dump），
  // 且 RF 内部 measured 就绪没有可靠的 effect 触发源，故以 DOM 实际渲染为准 rAF 轮询，每个剧本只 fit 一次。
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
        dom.length >= nodes.length &&
        [...dom].every((el) => el.getBoundingClientRect().width > 0);
      if (ready) {
        fittedFor.current = current;
        void fitView({ padding: 0.2, minZoom: 0.1, duration: 250 });
        return;
      }
      if (attempt < 1200) requestAnimationFrame(() => tryFit(attempt + 1));
    };
    const raf = requestAnimationFrame(() => tryFit(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [current, nodes, fitView]);

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
        void setCenter(n.position.x + rect.width / zoom / 2, n.position.y + rect.height / zoom / 2, {
          zoom: 1.1,
          duration: 300,
        });
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
      <div className="flow-dots flex h-full items-center justify-center text-sm text-zinc-600">
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
        fitViewOptions={{ padding: 0.2, minZoom: 0.1 }}
        minZoom={0.1}
        colorMode="dark"
        nodesConnectable={false}
        edgesFocusable={false}
        deleteKeyCode={["Delete", "Backspace"]}
        onPaneClick={() => select(null)}
      >
        <Controls showInteractive={false} />
        <MiniMap
          pannable
          zoomable
          nodeColor={(n) => MINIMAP_COLORS[n.type ?? ""] ?? "#a1a1aa"}
          nodeStrokeColor={() => "transparent"}
          maskColor="rgba(9, 9, 11, 0.75)"
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
