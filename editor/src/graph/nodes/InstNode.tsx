import { Handle, Position, type NodeProps } from "@xyflow/react";
import { Fragment } from "react";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

export function InstNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "inst") return null;
  const n = data.node;
  const entries = Object.entries(n.params);
  return (
    <NodeShell kind="inst" selected={selected} diags={data.diags} className="w-[240px]">
      <Handle type="target" position={Position.Top} />
      <div className="font-mono text-xs text-accent">{n.head}</div>
      {entries.length > 0 && (
        <div className="mt-1 grid grid-cols-[auto_1fr] gap-x-2 gap-y-0.5 font-mono text-[11px] leading-4">
          {entries.map(([k, v]) => (
            <Fragment key={k}>
              <span className="text-zinc-500">{k}</span>
              <span className="truncate text-zinc-300">{String(v)}</span>
            </Fragment>
          ))}
        </div>
      )}
      <Handle type="source" position={Position.Bottom} />
    </NodeShell>
  );
}
