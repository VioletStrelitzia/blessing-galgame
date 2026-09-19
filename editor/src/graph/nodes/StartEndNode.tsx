import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";

function Pill({
  label,
  selected,
  accent,
}: {
  label: string;
  selected?: boolean;
  accent?: boolean;
}) {
  return (
    <div
      className={`rounded-full border px-3 py-1 font-mono text-[10px] tracking-widest ${
        selected
          ? "border-accent/70 text-accent"
          : accent
            ? "border-accent/40 text-accent"
            : "border-white/15 text-zinc-500"
      }`}
    >
      {label}
    </div>
  );
}

export function StartNode({ selected }: NodeProps<FlowNode>) {
  return (
    <>
      <Pill label="START" selected={selected} accent />
      <Handle type="source" position={Position.Bottom} />
    </>
  );
}

export function EndNode({ selected }: NodeProps<FlowNode>) {
  return (
    <>
      <Handle type="target" position={Position.Top} />
      <Pill label="END" selected={selected} />
    </>
  );
}
