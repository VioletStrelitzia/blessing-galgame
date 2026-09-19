import { openScript } from "../state/io";
import { useEditor } from "../state/store";
import { Panel } from "./Panel";

export function ScriptList() {
  const scripts = useEditor((s) => s.scripts);
  const current = useEditor((s) => s.current);

  return (
    <Panel title="剧本" className="border-b border-white/8">
      <ul className="flex flex-col gap-0.5">
        {scripts.map((name) => (
          <li key={name}>
            <button
              onClick={() => void openScript(name)}
              className={`w-full rounded-md px-2 py-1.5 text-left font-mono text-xs transition-colors ${
                current === name
                  ? "bg-accent/10 text-accent"
                  : "text-zinc-400 hover:bg-white/[0.04] hover:text-zinc-200"
              }`}
            >
              {name}
            </button>
          </li>
        ))}
        {scripts.length === 0 && <li className="px-2 py-1 text-xs text-zinc-600">无剧本</li>}
      </ul>
    </Panel>
  );
}
