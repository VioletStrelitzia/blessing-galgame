import { Controls, MiniMap, ReactFlow, type NodeTypes } from "@xyflow/react";
import { useMemo } from "react";
import { useEditor } from "../store";
import { layoutGraph } from "./layout";
import { CondNode } from "./nodes/CondNode";
import { DialogueNode } from "./nodes/DialogueNode";
import { InstNode } from "./nodes/InstNode";
import { JumpNode } from "./nodes/JumpNode";
import { OptionGroupNode } from "./nodes/OptionGroupNode";
import { EndNode, StartNode } from "./nodes/StartEndNode";
import { toFlow } from "./toFlow";

const nodeTypes: NodeTypes = {
  start: StartNode,
  end: EndNode,
  dialogue: DialogueNode,
  inst: InstNode,
  option_group: OptionGroupNode,
  cond: CondNode,
  jump: JumpNode,
};

export function FlowCanvas() {
  const graph = useEditor((s) => s.graph);
  const selected = useEditor((s) => s.selected);
  const select = useEditor((s) => s.select);

  const { nodes, edges } = useMemo(() => {
    if (!graph) return { nodes: [], edges: [] };
    const flow = toFlow(graph);
    return { nodes: layoutGraph(flow.nodes, flow.edges), edges: flow.edges };
  }, [graph]);

  const rendered = useMemo(
    () => nodes.map((n) => ({ ...n, selected: n.id === selected })),
    [nodes, selected],
  );

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
        fitView
        colorMode="dark"
        nodesDraggable={false}
        nodesConnectable={false}
        edgesFocusable={false}
        onNodeClick={(_, node) => select(node.id)}
        onPaneClick={() => select(null)}
      >
        <Controls showInteractive={false} />
        <MiniMap pannable zoomable />
      </ReactFlow>
    </div>
  );
}
