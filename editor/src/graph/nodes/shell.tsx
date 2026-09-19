import type { CSSProperties, ReactNode } from "react";
import { useEditor } from "../../state/store";
import { kindColor } from "../kindColor";
import type { DiagBadge } from "../toFlow";

/** Archify 节点公式：不透明底色（color-mix 语义色 10% + panel）+ 1.5px 全饱和描边 + 6px 圆角，Flat-at-Rest */
export function NodeShell({
  kind,
  selected,
  editing,
  diags,
  collapseId,
  className,
  children,
}: {
  kind: string;
  selected?: boolean;
  /** 行内编辑态：描边与 ring 变为 accent（保持底色公式不变） */
  editing?: boolean;
  diags?: DiagBadge;
  /** 展开中的聚合链首节点：左上角给「收起」小按钮 */
  collapseId?: string;
  className?: string;
  children: ReactNode;
}) {
  const color = kindColor(kind);
  const style: CSSProperties = {
    ["--nc" as string]: color,
    backgroundColor: `color-mix(in srgb, ${color} 10%, #0F172A)`,
    borderColor: editing ? "#22D3EE" : color,
    outline: editing ? "2px solid #22D3EE" : selected ? `2px solid ${color}` : undefined,
    outlineOffset: 1,
  };
  return (
    <div
      style={style}
      className={`relative rounded-md border-[1.5px] px-3 py-2 ${className ?? ""}`}
    >
      {collapseId && (
        <button
          title="收起该链"
          className="nodrag absolute -top-2 -left-2 z-10 flex h-4 w-4 items-center justify-center rounded-sm border border-grid bg-panel font-mono text-[10px] leading-none text-mut hover:border-accent hover:text-accent"
          onClick={(e) => {
            e.stopPropagation();
            useEditor.getState().collapseGroup(collapseId);
          }}
        >
          −
        </button>
      )}
      <span
        style={{ color }}
        className={`absolute -top-2 rounded-sm bg-panel px-1.5 font-mono text-[10px] font-bold uppercase leading-4 tracking-[0.12em] ${collapseId ? "left-5" : "left-2"}`}
      >
        {kind}
      </span>
      {diags && (diags.error > 0 || diags.warning > 0) && (
        <span
          className={`absolute -top-2 right-2 rounded-sm border px-1.5 font-mono text-[10px] leading-4 ${
            diags.error > 0
              ? "border-danger bg-panel text-danger"
              : "border-warn bg-panel text-warn"
          }`}
        >
          {diags.error > 0 ? `E${diags.error}` : ""}
          {diags.warning > 0 ? `W${diags.warning}` : ""}
        </span>
      )}
      {children}
    </div>
  );
}

export function MiniBadge({ children }: { children: ReactNode }) {
  return (
    <span className="rounded-sm border border-grid bg-panel px-1 font-mono text-[10px] leading-4 text-mut">
      {children}
    </span>
  );
}
