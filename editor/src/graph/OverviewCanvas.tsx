// 剧本宏观关系总览画布：bgals-overview/1 → buildOverviewFlow（dagre LR）。
// 双击剧本节点下钻（openScript + 切回 detail）；拖动位置仅会话内保持（不入 sidecar）。

import {
  Controls,
  MarkerType,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type NodeChange,
  type NodeTypes,
} from "@xyflow/react";
import { useEffect, useMemo, useState } from "react";
import { openScript, showDetail } from "../state/io";
import { useEditor } from "../state/store";
import type { Pos } from "./layout";
import { OverviewGhostNode, OverviewScriptNode, OverviewTerminalNode } from "./nodes/OverviewNodes";
import { buildOverviewFlow, type OverviewFlowNode } from "./overview";

const nodeTypes: NodeTypes = {
  script: OverviewScriptNode,
  terminal: OverviewTerminalNode,
  ghost: OverviewGhostNode,
};

const defaultEdgeOptions = {
  type: "smoothstep",
  markerEnd: { type: MarkerType.ArrowClosed, width: 14, height: 14, color: "#64748B" },
} as const;

const MINIMAP_COLORS: Record<string, string> = {
  script: "#22D3EE",
  terminal: "#94A3B8",
  ghost: "#FB7185",
};

function Inner() {
  const overview = useEditor((s) => s.overview);
  const loading = useEditor((s) => s.overviewLoading);
  const selected = useEditor((s) => s.overviewSelected);
  const selectOverviewNode = useEditor((s) => s.selectOverviewNode);
  const { fitView, getNodes } = useReactFlow();

  // 每次载入重算布局（总览不做 sidecar 持久化）；自拖位置覆盖层随载入清空（渲染期调整）
  const base = useMemo(
    () => (overview ? buildOverviewFlow(overview) : { nodes: [], edges: [] }),
    [overview],
  );
  const [posMap, setPosMap] = useState<Map<string, Pos>>(new Map());
  const [posMapFor, setPosMapFor] = useState<typeof overview>(null);
  if (overview !== posMapFor) {
    setPosMapFor(overview);
    setPosMap(new Map());
  }

  const nodes = useMemo(
    () =>
      base.nodes.map((n) => ({
        ...n,
        position: posMap.get(n.id) ?? n.position,
        selected: n.id === selected,
      })),
    [base, posMap, selected],
  );

  // 节点少，直接全图 fit 一次（等测量完成）
  useEffect(() => {
    if (!overview) return;
    let alive = true;
    const tryFit = (attempt: number) => {
      if (!alive) return;
      const ns = getNodes();
      if (ns.length > 0 && ns.every((n) => n.measured?.width !== undefined)) {
        void fitView({ padding: 0.3, duration: 250 });
        return;
      }
      if (attempt < 90) requestAnimationFrame(() => tryFit(attempt + 1));
    };
    const raf = requestAnimationFrame(() => tryFit(0));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
  }, [overview, fitView, getNodes]);

  const onNodesChange = (changes: NodeChange<OverviewFlowNode>[]) => {
    for (const ch of changes) {
      if (ch.type === "position" && ch.position) {
        setPosMap((m) => new Map(m).set(ch.id, ch.position!));
      } else if (ch.type === "select") {
        if (ch.selected) selectOverviewNode(ch.id);
        else if (useEditor.getState().overviewSelected === ch.id) selectOverviewNode(null);
      }
    }
  };

  const drillDown = (name: string) => {
    showDetail();
    void openScript(name);
  };

  if (loading || !overview) {
    return (
      <div className="flow-dots flex h-full items-center justify-center text-sm text-dim">
        {loading ? "加载总览…" : "无总览数据"}
      </div>
    );
  }

  return (
    <div className="flow-dots h-full">
      <ReactFlow
        nodes={nodes}
        edges={base.edges}
        nodeTypes={nodeTypes}
        onNodesChange={onNodesChange}
        onNodeDoubleClick={(_, node) => {
          if (node.type === "script") drillDown(node.id);
        }}
        onPaneClick={() => selectOverviewNode(null)}
        defaultEdgeOptions={defaultEdgeOptions}
        fitViewOptions={{ padding: 0.3 }}
        colorMode="dark"
        zoomOnDoubleClick={false}
        nodeClickDistance={10}
        nodesConnectable={false}
        edgesFocusable={false}
        deleteKeyCode={null}
      >
        <Controls showInteractive={false} />
        <MiniMap
          pannable
          zoomable
          nodeColor={(n) => MINIMAP_COLORS[n.type ?? ""] ?? "#a1a1aa"}
          nodeStrokeColor={() => "transparent"}
          maskColor="rgba(2, 6, 23, 0.75)"
        />
      </ReactFlow>
    </div>
  );
}

export function OverviewCanvas() {
  return (
    <ReactFlowProvider>
      <Inner />
    </ReactFlowProvider>
  );
}
