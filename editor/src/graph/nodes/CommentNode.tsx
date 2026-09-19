// comment 节点：不参与连线的游离便签（无 Handle），附着目标存在时显示 before 提示。
// 同一节点公式：不透明底色 + 1.5px 语义色（灰）描边 + 6px 圆角，无阴影；双击行内编辑文本。

import type { NodeProps } from "@xyflow/react";
import { useRef } from "react";
import { AutoTextarea } from "../../components/controls";
import { resolveInlineKey, useInlineEdit } from "../../components/inlineEdit";
import { patchComment } from "../../state/edit";
import { kindColor } from "../kindColor";
import type { FlowNode } from "../toFlow";

export function CommentNode({ data, selected }: NodeProps<FlowNode>) {
  const node = data.node;
  const isComment = node.kind === "comment";
  const edit = useInlineEdit({ text: isComment ? node.text : "" }, (d) => {
    if (isComment) patchComment(node.id, d.text);
  });
  const boxRef = useRef<HTMLDivElement>(null);
  if (!isComment) return null;
  const n = node;

  const editing = edit.draft !== null;
  const color = kindColor("comment");
  return (
    <div
      style={{
        borderColor: editing ? "#22D3EE" : color,
        backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)`,
        outline: editing ? "2px solid #22D3EE" : selected ? `2px solid ${color}` : undefined,
        outlineOffset: 1,
      }}
      className="relative w-[200px] rounded-md border-[1.5px] px-3 py-2"
    >
      <div
        style={{ color }}
        className="absolute -top-2 left-2 rounded-sm bg-panel px-1.5 font-mono text-[10px] font-bold uppercase leading-4 tracking-[0.12em]"
      >
        # 注释{n.before !== null && <span className="text-dim"> @ {n.before}</span>}
      </div>
      {edit.draft !== null ? (
        <div
          ref={boxRef}
          className="nodrag nopan"
          onBlur={(e) => {
            if (!boxRef.current?.contains(e.relatedTarget as Node | null)) edit.submit();
          }}
        >
          <AutoTextarea
            value={edit.draft.text}
            autoFocus
            onChange={(v) => edit.setDraft({ text: v })}
            onKeyDown={(e) => {
              const action = resolveInlineKey(e.key, e.shiftKey);
              if (action === "submit") {
                e.preventDefault();
                edit.submit();
              } else if (action === "cancel") {
                e.preventDefault();
                edit.cancel();
              }
            }}
            className="w-full border-b border-grid bg-transparent text-xs leading-relaxed break-all whitespace-pre-wrap text-ink outline-none focus:border-accent"
          />
          <div className="mt-1 font-mono text-[9px] text-dim">Enter 提交 · Esc 取消</div>
        </div>
      ) : (
        <div
          className="line-clamp-4 text-xs leading-relaxed break-all whitespace-pre-wrap text-mut"
          title="双击行内编辑"
          onDoubleClick={(e) => {
            e.stopPropagation();
            edit.start();
          }}
        >
          {n.text || <span className="text-dim">（空注释）</span>}
        </div>
      )}
      {data.diags && (data.diags.error > 0 || data.diags.warning > 0) && (
        <span className="absolute -top-2 right-2 rounded-sm border border-danger bg-panel px-1.5 font-mono text-[10px] leading-4 text-danger">
          {data.diags.error > 0 ? data.diags.error : data.diags.warning}
        </span>
      )}
    </div>
  );
}
