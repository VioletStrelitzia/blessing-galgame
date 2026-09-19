// 聚合视图节点：连续同类链的折叠形态。胶囊 kind 标签（DIALOGUE ×12）+ 首 2 尾 1 摘要，
// 中间「… 展开其余 N 条」按钮；不可选中编辑（toFlow 置 selectable/draggable false）。

import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { GraphNode } from "../../../shared/graph";
import { TailText } from "../../components/TailText";
import { useEditor } from "../../state/store";
import { isGroupNode } from "../collapse";
import { kindColor } from "../kindColor";
import type { FlowNode } from "../toFlow";

function summaryLine(n: GraphNode): string {
  if (n.kind === "dialogue") {
    const t = n.display_text || n.text;
    const cut = t.length > 18 ? `${t.slice(0, 18)}…` : t;
    return n.character ? `${n.character}: ${cut}` : cut;
  }
  if (n.kind === "inst") {
    const first = Object.entries(n.params)[0];
    return first ? `${n.head} ${first[0]}=${String(first[1])}` : n.head;
  }
  return n.kind;
}

export function RunGroupNode({ data }: NodeProps<FlowNode>) {
  const expandGroup = useEditor((s) => s.expandGroup);
  if (!isGroupNode(data.node)) return null;
  const g = data.node;
  const color = kindColor(g.groupKind);
  return (
    <div
      style={{ borderColor: color, backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)` }}
      className="relative w-[260px] cursor-pointer rounded-md border-[1.5px] px-3 py-2"
      title="点击展开该链（点击空白处经 React Flow onNodeClick 处理，拖动不触发）"
    >
      <Handle type="target" position={Position.Top} />
      <span
        style={{ color }}
        className="absolute -top-2 left-2 rounded-sm bg-panel px-1.5 font-mono text-[10px] font-bold uppercase leading-4 tracking-[0.12em]"
      >
        {g.groupKind} ×{g.runIds.length}
      </span>
      <div className="flex flex-col gap-0.5 font-mono text-[11px] leading-5 text-mut">
        {g.summary.slice(0, 2).map((n) => (
          <TailText key={n.id} text={summaryLine(n)} max={30} className="block overflow-hidden" />
        ))}
      </div>
      <button
        className="nodrag my-1 w-full rounded-sm border border-grid bg-panel px-2 py-0.5 font-mono text-[10px] text-mut transition-colors hover:border-accent hover:text-accent"
        onClick={(e) => {
          e.stopPropagation();
          expandGroup(g.id, g.runIds);
        }}
      >
        … 展开其余 {g.hiddenCount} 条
      </button>
      <div className="font-mono text-[11px] leading-5 text-mut">
        <TailText text={summaryLine(g.summary[2])} max={30} className="block overflow-hidden" />
      </div>
      <Handle type="source" position={Position.Bottom} />
    </div>
  );
}
