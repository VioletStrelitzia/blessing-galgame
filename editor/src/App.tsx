import { useEffect } from "react";
import { FlowCanvas } from "./graph/FlowCanvas";
import { Diagnostics } from "./panels/Diagnostics";
import { Inspector } from "./panels/Inspector";
import { ScriptList } from "./panels/ScriptList";
import { useEditor } from "./store";

function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full border border-white/10 bg-white/[0.03] px-2 py-0.5 font-mono text-[10px] text-zinc-400">
      {children}
    </span>
  );
}

export default function App() {
  const init = useEditor((s) => s.init);
  const graph = useEditor((s) => s.graph);
  const checking = useEditor((s) => s.checking);
  const runCheck = useEditor((s) => s.runCheck);
  const error = useEditor((s) => s.error);

  useEffect(() => {
    void init();
  }, [init]);

  return (
    <div className="flex h-screen flex-col font-sans">
      <header className="flex h-11 shrink-0 items-center gap-3 border-b border-white/8 px-4">
        <span className="font-mono text-sm font-semibold text-accent">BGalS</span>
        <span className="text-sm text-zinc-200">{graph?.script ?? "…"}</span>
        {graph && <Badge>{graph.compiler}</Badge>}
        {graph && <Badge>{graph.format}</Badge>}
        <div className="flex-1" />
        <button
          onClick={() => void runCheck()}
          disabled={checking}
          className="rounded-md border border-accent/40 px-3 py-1 font-mono text-xs text-accent transition-colors hover:bg-accent/10 disabled:opacity-40"
        >
          {checking ? "检查中…" : "检查"}
        </button>
      </header>
      <div className="flex min-h-0 flex-1">
        <aside className="flex w-60 shrink-0 flex-col border-r border-white/8 bg-white/[0.03]">
          <ScriptList />
          <Diagnostics />
        </aside>
        <main className="min-w-0 flex-1">
          <FlowCanvas />
        </main>
        <aside className="w-80 shrink-0 border-l border-white/8 bg-white/[0.03]">
          <Inspector />
        </aside>
      </div>
      {error && (
        <div className="border-t border-danger/30 bg-danger/10 px-4 py-1.5 font-mono text-xs text-danger">
          {error}
        </div>
      )}
    </div>
  );
}
