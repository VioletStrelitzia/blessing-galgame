import { useEffect } from "react";
import { InsertMenu } from "./components/InsertMenu";
import { Toolbar } from "./components/Toolbar";
import { VerifyBanner } from "./components/VerifyBanner";
import { startDevBridge } from "./dev/bridge";
import { FlowCanvas } from "./graph/FlowCanvas";
import { Diagnostics } from "./panels/Diagnostics";
import { Inspector } from "./panels/Inspector";
import { ScriptList } from "./panels/ScriptList";
import { init, save } from "./state/io";
import { useEditor } from "./state/store";

function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full border border-white/10 bg-white/[0.03] px-2 py-0.5 font-mono text-[10px] text-zinc-400">
      {children}
    </span>
  );
}

function useGlobalKeys() {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const inField =
        target !== null &&
        (/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable);
      const mod = e.ctrlKey || e.metaKey;
      if (mod && e.key.toLowerCase() === "s") {
        e.preventDefault();
        void save();
        return;
      }
      if (inField) return; // 输入框内保留原生编辑键
      if (mod && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) useEditor.getState().redo();
        else useEditor.getState().undo();
      } else if (mod && e.key.toLowerCase() === "y") {
        e.preventDefault();
        useEditor.getState().redo();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
}

export default function App() {
  const graph = useEditor((s) => s.graph);
  const mode = useEditor((s) => s.mode);
  const dirty = useEditor((s) => s.dirty);
  const error = useEditor((s) => s.error);
  const setError = useEditor((s) => s.setError);

  useEffect(() => {
    void init();
    void startDevBridge();
  }, []);
  useGlobalKeys();

  return (
    <div className="flex h-screen flex-col font-sans">
      <header className="flex h-11 shrink-0 items-center gap-3 border-b border-white/8 px-4">
        <span className="font-mono text-sm font-semibold text-accent">BGalS</span>
        <span className="flex items-center gap-1.5 text-sm text-zinc-200">
          {graph?.script ?? "…"}
          {dirty && <span className="h-1.5 w-1.5 rounded-full bg-warn" title="有未保存的修改" />}
        </span>
        {graph && <Badge>{graph.compiler}</Badge>}
        {graph && <Badge>{graph.format}</Badge>}
        {mode === "fixtures" && <Badge>fixtures · 只读数据</Badge>}
        <div className="flex-1" />
      </header>
      <VerifyBanner />
      <div className="flex min-h-0 flex-1">
        <aside className="flex w-60 shrink-0 flex-col border-r border-white/8 bg-white/[0.03]">
          <ScriptList />
          <Diagnostics />
        </aside>
        <main className="flex min-w-0 flex-1 flex-col">
          <Toolbar />
          <div className="min-h-0 flex-1">
            <FlowCanvas />
          </div>
        </main>
        <aside className="w-80 shrink-0 border-l border-white/8 bg-white/[0.03]">
          <Inspector />
        </aside>
      </div>
      {error && (
        <div className="flex shrink-0 items-center gap-2 border-t border-danger/30 bg-danger/10 px-4 py-1.5">
          <span className="font-mono text-xs text-danger">{error}</span>
          <div className="flex-1" />
          <button
            onClick={() => setError(null)}
            className="font-mono text-xs text-zinc-500 hover:text-zinc-300"
          >
            ×
          </button>
        </div>
      )}
      <InsertMenu />
    </div>
  );
}
