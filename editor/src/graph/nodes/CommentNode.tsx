// comment 节点：不参与连线的游离便签（无 Handle），附着目标存在时显示 before 提示。

import type { NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";

export function CommentNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "comment") return null;
  const n = data.node;
  return (
    <div
      className={`relative w-[200px] rounded-md border px-3 py-2 shadow-lg transition-colors ${
        selected ? "border-warn/70 bg-warn/[0.12]" : "border-warn/25 bg-warn/[0.06]"
      }`}
    >
      <div className="mb-1 font-mono text-[10px] tracking-widest text-warn/60">
        # 注释{n.before !== null && <span className="text-zinc-600"> @ {n.before}</span>}
      </div>
      <div className="line-clamp-4 text-xs leading-relaxed break-all whitespace-pre-wrap text-zinc-300">
        {n.text || <span className="text-zinc-600">（空注释）</span>}
      </div>
      {data.diags && (data.diags.error > 0 || data.diags.warning > 0) && (
        <span className="absolute -top-2 right-2 rounded-full border border-danger/60 bg-danger/15 px-1.5 font-mono text-[10px] leading-4 text-danger">
          {data.diags.error > 0 ? data.diags.error : data.diags.warning}
        </span>
      )}
    </div>
  );
}
