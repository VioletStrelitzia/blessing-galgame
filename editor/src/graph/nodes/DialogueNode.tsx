import { Handle, Position, type NodeProps } from "@xyflow/react";
import { useRef } from "react";
import { AutoTextarea } from "../../components/controls";
import { resolveInlineKey, useInlineEdit } from "../../components/inlineEdit";
import { patchDialogue } from "../../state/edit";
import type { FlowNode } from "../toFlow";
import { MiniBadge, NodeShell } from "./shell";

/** 行内编辑输入：透明底 + 1px 下划线，与节点排版同字级不跳动 */
const inlineInput =
  "w-full border-b border-grid bg-transparent outline-none placeholder:text-dim focus:border-accent";

export function DialogueNode({ data, selected }: NodeProps<FlowNode>) {
  const node = data.node;
  const isDialogue = node.kind === "dialogue";
  const edit = useInlineEdit(
    { character: isDialogue ? node.character : "", text: isDialogue ? node.text : "" },
    (d) => {
      if (isDialogue) patchDialogue(node.id, { character: d.character, text: d.text });
    },
  );
  const boxRef = useRef<HTMLDivElement>(null);
  if (!isDialogue) return null;
  const n = node;

  const onKeyDown = (e: React.KeyboardEvent) => {
    const action = resolveInlineKey(e.key, e.shiftKey);
    if (action === "submit") {
      e.preventDefault();
      edit.submit();
    } else if (action === "cancel") {
      e.preventDefault();
      edit.cancel();
    }
  };

  return (
    <NodeShell
      kind="dialogue"
      selected={selected}
      editing={edit.editing}
      diags={data.diags}
      collapseId={data.collapseId}
      className="w-[280px]"
    >
      <Handle type="target" position={Position.Top} />
      {edit.editing && edit.draft ? (
        <div
          ref={boxRef}
          className="nodrag nopan"
          onBlur={(e) => {
            // 字段间 Tab 不提交；焦点离开整个编辑容器才提交
            if (!boxRef.current?.contains(e.relatedTarget as Node | null)) edit.submit();
          }}
        >
          <input
            value={edit.draft.character}
            placeholder="（旁白）"
            onChange={(e) => edit.setDraft({ character: e.target.value })}
            onKeyDown={onKeyDown}
            className={`${inlineInput} mb-0.5 text-xs font-semibold text-accent`}
          />
          <AutoTextarea
            value={edit.draft.text}
            autoFocus
            onChange={(v) => edit.setDraft({ text: v })}
            onKeyDown={onKeyDown}
            className={`${inlineInput} text-sm leading-relaxed text-ink`}
          />
          <div className="mt-1 font-mono text-[9px] text-dim">
            Enter 提交 · Shift+Enter 换行 · Esc 取消
          </div>
        </div>
      ) : (
        <div
          onDoubleClick={(e) => {
            e.stopPropagation();
            edit.start();
          }}
          title="双击行内编辑"
        >
          {n.character && (
            <div className="mb-0.5 text-xs font-semibold text-accent">{n.character}</div>
          )}
          <div className="line-clamp-4 text-sm leading-relaxed text-ink">{n.display_text}</div>
          {(n.prev.length > 0 || n.post.length > 0 || n.anchors.length > 0) && (
            <div className="mt-1.5 flex gap-1">
              {n.prev.length > 0 && <MiniBadge>&lt; {n.prev.length}</MiniBadge>}
              {n.post.length > 0 && <MiniBadge>&gt; {n.post.length}</MiniBadge>}
              {n.anchors.length > 0 && <MiniBadge>[ ] {n.anchors.length}</MiniBadge>}
            </div>
          )}
        </div>
      )}
      <Handle type="source" position={Position.Bottom} />
    </NodeShell>
  );
}
