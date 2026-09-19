// seq 顺序边：正交折线（getSmoothStepPath，8px 圆角）；hover 在中点显示「+」插入菜单。
// 触及聚合组节点的合成边（或聚合产生的边界边）不显示「+」。
// 命中区为宽透明路径；按钮常驻但 hover 前透明（pointer-events 保持，避免路径→按钮的闪烁）。

import { BaseEdge, EdgeLabelRenderer, getSmoothStepPath, type EdgeProps } from "@xyflow/react";
import { useState } from "react";
import { useEditor } from "../../state/store";
import type { FlowEdgeData } from "../toFlow";

export function SeqEdge(props: EdgeProps) {
  const [hover, setHover] = useState(false);
  const openInsertMenu = useEditor((s) => s.openInsertMenu);
  const [path, labelX, labelY] = getSmoothStepPath({
    sourceX: props.sourceX,
    sourceY: props.sourceY,
    sourcePosition: props.sourcePosition,
    targetX: props.targetX,
    targetY: props.targetY,
    targetPosition: props.targetPosition,
    borderRadius: 8,
  });
  const data = props.data as FlowEdgeData | undefined;
  const insertable = data !== undefined && !data.synthetic;
  return (
    <>
      <BaseEdge id={props.id} path={path} markerEnd={props.markerEnd} />
      <path
        d={path}
        fill="none"
        stroke="transparent"
        strokeWidth={20}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
      />
      {insertable && (
        <EdgeLabelRenderer>
          <button
            title="在此插入节点"
            className={`nodrag nopan pointer-events-auto absolute flex h-[18px] w-[18px] items-center justify-center rounded-full border font-mono text-[11px] leading-none transition-all ${
              hover
                ? "border-accent bg-panel text-accent"
                : "pointer-events-auto border-transparent text-transparent"
            }`}
            style={{
              transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
              opacity: hover ? 1 : 0,
            }}
            onMouseEnter={() => setHover(true)}
            onMouseLeave={() => setHover(false)}
            onClick={(e) => {
              e.stopPropagation();
              if (data) openInsertMenu({ edgeIndex: data.edgeIndex, x: e.clientX, y: e.clientY });
            }}
          >
            +
          </button>
        </EdgeLabelRenderer>
      )}
    </>
  );
}
