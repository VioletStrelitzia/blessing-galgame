// 总览视图节点：剧本（青，begin 绿描边 + BEGIN 标签）、main_menu 终态胶囊（灰）、
// missing 目标幽灵（玫瑰色虚线）。同一 Archify 公式：不透明色混底 + 1.5px 描边 + 6px 圆角。

import { Handle, Position, type NodeProps } from "@xyflow/react";
import { statsLine, type OverviewFlowNode } from "../overview";

export function OverviewScriptNode({ data, selected }: NodeProps<OverviewFlowNode>) {
  const color = data.begin ? "#34D399" : "#22D3EE";
  return (
    <div
      style={{
        borderColor: color,
        backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)`,
        outline: selected ? `2px solid ${color}` : undefined,
        outlineOffset: 1,
      }}
      className="relative w-[220px] rounded-md border-[1.5px] px-3 py-2"
      title="双击打开剧本"
    >
      <Handle type="target" position={Position.Left} />
      {data.begin && (
        <span className="absolute -top-2 left-2 rounded-sm bg-panel px-1.5 font-mono text-[10px] font-bold uppercase leading-4 tracking-[0.12em] text-ok">
          begin
        </span>
      )}
      <div className="font-mono text-xs font-semibold text-ink">{data.label}</div>
      {data.stats && (
        <div className="mt-0.5 font-mono text-[10px] text-mut">{statsLine(data.stats)}</div>
      )}
      <Handle type="source" position={Position.Right} />
    </div>
  );
}

export function OverviewTerminalNode({ data, selected }: NodeProps<OverviewFlowNode>) {
  const color = "#94A3B8";
  return (
    <div
      style={{
        borderColor: color,
        backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)`,
        outline: selected ? `2px solid ${color}` : undefined,
        outlineOffset: 1,
      }}
      className="rounded-full border-[1.5px] px-3 py-1.5"
    >
      <Handle type="target" position={Position.Left} />
      <div className="font-mono text-[10px] font-bold uppercase tracking-[0.12em] text-mut">
        {data.label}
      </div>
    </div>
  );
}

export function OverviewGhostNode({ data, selected }: NodeProps<OverviewFlowNode>) {
  const color = "#FB7185";
  return (
    <div
      style={{
        borderColor: color,
        backgroundColor: `color-mix(in srgb, ${color} 5%, #0F172A)`,
        outline: selected ? `2px solid ${color}` : undefined,
        outlineOffset: 1,
      }}
      className="relative w-[180px] rounded-md border-[1.5px] border-dashed px-3 py-2"
      title="目标剧本不存在"
    >
      <Handle type="target" position={Position.Left} />
      <div className="font-mono text-xs font-semibold text-danger">{data.label}</div>
      <div className="mt-0.5 font-mono text-[10px] text-dim">目标剧本不存在</div>
    </div>
  );
}
