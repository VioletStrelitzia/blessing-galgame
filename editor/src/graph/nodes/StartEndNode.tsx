import { Handle, Position, type NodeProps } from "@xyflow/react";
import { kindColor } from "../kindColor";
import type { FlowNode } from "../toFlow";

function Pill({
  kind,
  label,
  selected,
}: {
  kind: "start" | "end";
  label: string;
  selected?: boolean;
}) {
  const color = kindColor(kind);
  return (
    <div
      style={{
        borderColor: color,
        backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)`,
        color,
        outline: selected ? `2px solid ${color}` : undefined,
        outlineOffset: 1,
      }}
      className="rounded-full border-[1.5px] px-3 py-1 font-mono text-[10px] font-bold uppercase tracking-[0.12em]"
    >
      {label}
    </div>
  );
}

export function StartNode({ selected }: NodeProps<FlowNode>) {
  return (
    <>
      <Pill kind="start" label="start" selected={selected} />
      <Handle type="source" position={Position.Bottom} />
    </>
  );
}

export function EndNode({ selected }: NodeProps<FlowNode>) {
  return (
    <>
      <Handle type="target" position={Position.Top} />
      <Pill kind="end" label="end" selected={selected} />
    </>
  );
}
