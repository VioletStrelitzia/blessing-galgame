import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

const ROW_H = 24;
const PAD_TOP = 8;

export function OptionGroupNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "option_group") return null;
  return (
    <NodeShell kind="option" selected={selected} diags={data.diags} className="w-[240px]">
      <Handle type="target" position={Position.Top} />
      <div>
        {data.rows.map((r) => (
          <div
            key={r.handle}
            className="flex items-center gap-1.5 text-xs"
            style={{ height: ROW_H }}
          >
            <span className="font-mono text-accent">*</span>
            <span className="truncate text-zinc-200">{r.text}</span>
            {r.cond && (
              <span className="truncate font-mono text-[10px] text-warn">if:{r.cond}</span>
            )}
          </div>
        ))}
      </div>
      {data.rows.map((r, i) => (
        <Handle
          key={r.handle}
          id={r.handle}
          type="source"
          position={Position.Right}
          style={{ top: PAD_TOP + i * ROW_H + ROW_H / 2 }}
        />
      ))}
    </NodeShell>
  );
}
