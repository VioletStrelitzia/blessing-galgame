import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { FlowNode } from "../toFlow";
import { MiniBadge, NodeShell } from "./shell";

export function DialogueNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "dialogue") return null;
  const n = data.node;
  return (
    <NodeShell kind="dialogue" selected={selected} diags={data.diags} className="w-[280px]">
      <Handle type="target" position={Position.Top} />
      {n.character && <div className="mb-0.5 text-xs font-medium text-accent">{n.character}</div>}
      <div className="line-clamp-4 text-sm leading-relaxed text-zinc-200">{n.display_text}</div>
      {(n.prev.length > 0 || n.post.length > 0 || n.anchors.length > 0) && (
        <div className="mt-1.5 flex gap-1">
          {n.prev.length > 0 && <MiniBadge>&lt; {n.prev.length}</MiniBadge>}
          {n.post.length > 0 && <MiniBadge>&gt; {n.post.length}</MiniBadge>}
          {n.anchors.length > 0 && <MiniBadge>[ ] {n.anchors.length}</MiniBadge>}
        </div>
      )}
      <Handle type="source" position={Position.Bottom} />
    </NodeShell>
  );
}
