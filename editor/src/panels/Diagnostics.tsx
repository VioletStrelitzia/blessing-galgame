import { useState } from "react";
import { scriptNameOfFile, type Diag } from "../../shared/check";
import { useEditor } from "../store";
import { Panel } from "./Panel";

function levelStyle(level: string): string {
  return level === "error" ? "text-danger" : "text-warn";
}

/** 诊断 → 节点定位。bgals-graph/1 节点暂无行号字段（M3 补齐），当前尽力匹配：带 line 的节点取行号不超过诊断行的最近者 */
function locateNodeId(diag: Diag): string | null {
  const { graph } = useEditor.getState();
  if (!graph || scriptNameOfFile(diag.file) !== graph.script) return null;
  let best: { id: string; line: number } | null = null;
  for (const n of graph.nodes) {
    const line = (n as { line?: number }).line;
    if (typeof line !== "number") continue;
    if (line <= diag.line && (best === null || line > best.line)) best = { id: n.id, line };
  }
  return best?.id ?? null;
}

function DiagItem({ diag }: { diag: Diag }) {
  const current = useEditor((s) => s.current);
  const select = useEditor((s) => s.select);
  const [active, setActive] = useState(false);
  const inCurrent = current !== null && scriptNameOfFile(diag.file) === current;
  return (
    <button
      disabled={!inCurrent}
      onClick={() => {
        setActive(true);
        select(locateNodeId(diag));
      }}
      className={`w-full rounded-md px-2 py-1.5 text-left transition-colors ${
        inCurrent ? "hover:bg-white/[0.04]" : "cursor-default opacity-45"
      } ${active ? "bg-white/[0.04]" : ""}`}
    >
      <span className={`font-mono text-[10px] ${levelStyle(diag.level)}`}>
        {diag.file.replace(/^res:\/\//, "")}:{diag.line}
      </span>
      <div className="mt-0.5 text-xs leading-relaxed text-zinc-300">{diag.msg}</div>
    </button>
  );
}

export function Diagnostics() {
  const report = useEditor((s) => s.report);
  const diags = report?.diags ?? [];
  const errors = diags.filter((d) => d.level === "error");
  const warnings = diags.filter((d) => d.level !== "error");

  return (
    <Panel
      title="诊断"
      className="flex-1"
      action={
        report && (
          <span className={`font-mono text-[10px] ${report.ok ? "text-zinc-500" : "text-danger"}`}>
            {report.ok ? "ok" : "failed"} · {diags.length}
          </span>
        )
      }
    >
      {!report && <div className="px-2 py-1 text-xs text-zinc-600">点击顶栏「检查」运行</div>}
      {report && diags.length === 0 && (
        <div className="px-2 py-1 text-xs text-zinc-600">无诊断，全部通过</div>
      )}
      {errors.length > 0 && (
        <div className="mb-2">
          <div className="px-2 py-1 font-mono text-[10px] tracking-widest text-danger">
            ERROR · {errors.length}
          </div>
          {errors.map((d, i) => (
            <DiagItem key={`e${i}`} diag={d} />
          ))}
        </div>
      )}
      {warnings.length > 0 && (
        <div>
          <div className="px-2 py-1 font-mono text-[10px] tracking-widest text-warn">
            WARNING · {warnings.length}
          </div>
          {warnings.map((d, i) => (
            <DiagItem key={`w${i}`} diag={d} />
          ))}
        </div>
      )}
    </Panel>
  );
}
