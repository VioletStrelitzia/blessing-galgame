import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

export function JumpNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "jump") return null;
  return (
    <NodeShell kind="jump" selected={selected}>
      <Handle type="target" position={Position.Top} />
      <div className="font-mono text-xs">
        <span className="text-zinc-500">→ </span>
        <span className={data.node.target === "main_menu" ? "text-warn" : "text-accent"}>
          {data.node.target}
        </span>
      </div>
    </NodeShell>
  );
}
