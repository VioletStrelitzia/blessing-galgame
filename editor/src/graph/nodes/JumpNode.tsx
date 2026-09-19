import { Handle, Position, type NodeProps } from "@xyflow/react";
import { TailText } from "../../components/TailText";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

export function JumpNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "jump") return null;
  return (
    <NodeShell kind="jump" selected={selected} diags={data.diags}>
      <Handle type="target" position={Position.Top} />
      <div className="flex font-mono text-xs">
        <span className="mr-1 shrink-0 text-dim">→</span>
        <TailText
          text={data.node.target}
          max={24}
          className={`overflow-hidden ${data.node.target === "main_menu" ? "text-warn" : "text-danger"}`}
        />
      </div>
    </NodeShell>
  );
}
