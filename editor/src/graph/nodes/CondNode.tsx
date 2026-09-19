import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

export function CondNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "cond") return null;
  return (
    <NodeShell kind="cond" selected={selected} diags={data.diags} className="w-[220px]">
      <Handle type="target" position={Position.Top} />
      <div className="flex flex-col gap-0.5">
        {data.rows.map((r, i) => (
          <div key={r.handle} className="truncate font-mono text-[11px] leading-5">
            <span className="text-accent">{i === 0 ? "if" : r.cond ? "elif" : "else"}</span>
            {r.cond && <span className="text-zinc-300"> {r.cond}</span>}
          </div>
        ))}
      </div>
      <Handle type="source" position={Position.Bottom} />
    </NodeShell>
  );
}
