import type { ReactNode } from "react";

export function Panel({
  title,
  action,
  children,
  className,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`flex min-h-0 flex-col ${className ?? ""}`}>
      <header className="flex h-8 shrink-0 items-center justify-between border-b border-white/8 px-3">
        <span className="font-mono text-[10px] tracking-widest text-zinc-500 uppercase">
          {title}
        </span>
        {action}
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto p-2">{children}</div>
    </section>
  );
}
