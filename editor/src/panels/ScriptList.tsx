import { openScript, showDetail } from "../state/io";
import { useEditor } from "../state/store";
import { Panel } from "./Panel";

export function ScriptList() {
  const scripts = useEditor((s) => s.scripts);
  const current = useEditor((s) => s.current);
  const view = useEditor((s) => s.view);

  return (
    <Panel title="剧本" className="border-b border-grid">
      <ul className="flex flex-col gap-0.5">
        {scripts.map((name) => (
          <li key={name}>
            <button
              onClick={() => {
                if (view !== "detail") showDetail(); // 总览下点击 = 切回 detail 并打开
                void openScript(name);
              }}
              className={`w-full rounded-md px-2 py-1.5 text-left font-mono text-xs transition-colors ${
                current === name && view === "detail"
                  ? "bg-accent/10 text-accent"
                  : "text-mut hover:bg-grid/40 hover:text-ink"
              }`}
            >
              {name}
            </button>
          </li>
        ))}
        {scripts.length === 0 && <li className="px-2 py-1 text-xs text-dim">无剧本</li>}
      </ul>
    </Panel>
  );
}
