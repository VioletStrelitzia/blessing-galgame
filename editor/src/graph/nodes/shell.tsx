import type { ReactNode } from "react";
import type { DiagBadge } from "../toFlow";

export function NodeShell({
  kind,
  selected,
  diags,
  className,
  children,
}: {
  kind: string;
  selected?: boolean;
  diags?: DiagBadge;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={`relative rounded-lg border px-3 py-2 backdrop-blur-md transition-colors ${
        selected ? "border-accent/70 bg-white/[0.07]" : "border-white/10 bg-white/[0.04]"
      } ${className ?? ""}`}
    >
      <span className="absolute -top-2 left-2 rounded-full border border-accent/40 bg-base px-1.5 font-mono text-[10px] leading-4 text-accent">
        {kind}
      </span>
      {diags && (diags.error > 0 || diags.warning > 0) && (
        <span
          className={`absolute -top-2 right-2 rounded-full border px-1.5 font-mono text-[10px] leading-4 ${
            diags.error > 0
              ? "border-danger/60 bg-danger/15 text-danger"
              : "border-warn/60 bg-warn/15 text-warn"
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
    <span className="rounded border border-white/10 bg-white/[0.04] px-1 font-mono text-[10px] leading-4 text-zinc-400">
      {children}
    </span>
  );
}
