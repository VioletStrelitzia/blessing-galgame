import { Handle, Position, type NodeProps } from "@xyflow/react";
import { TailText } from "../../components/TailText";
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
            className="flex items-center gap-1.5 overflow-hidden text-xs"
            style={{ height: ROW_H }}
          >
            <span className="shrink-0 font-mono text-warn">*</span>
            <TailText text={r.text ?? ""} max={18} className="overflow-hidden text-ink" />
            {r.cond && (
              <TailText
                text={`if:${r.cond}`}
                max={16}
                className="overflow-hidden font-mono text-[10px] text-warn"
              />
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
