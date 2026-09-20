// 展开聚合链的分组边界框（Archify 风格）：圆角 12px、1px 虚线语义色描边、5% 色混底、
// 左上角小标签。纯展示：无 Handle，selectable/draggable/focusable=false，zIndex -1 压底，
// pointerEvents none（点击穿透到成员/画布）。

import type { NodeProps } from "@xyflow/react";
import type { FrameFlowNode } from "../toFlow";

export function FrameNode({ data }: NodeProps<FrameFlowNode>) {
  const { label, color } = data.frame;
  return (
    <div
      style={{
        borderColor: color,
        backgroundColor: `color-mix(in srgb, ${color} 5%, transparent)`,
      }}
      className="h-full w-full rounded-xl border border-dashed"
    >
      <span
        style={{ color }}
        className="absolute top-2.5 left-3 font-mono text-[10px] font-bold uppercase tracking-[0.12em]"
      >
        {label}
      </span>
    </div>
  );
}
