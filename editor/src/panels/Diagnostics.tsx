import { scriptNameOfFile, type Diag } from "../../shared/check";
import { useEditor } from "../state/store";
import { Panel } from "./Panel";

function levelStyle(level: string): string {
  return level === "error" ? "text-danger" : "text-warn";
}

function DiagItem({ diag, nodeId }: { diag: Diag; nodeId: string | null }) {
  const current = useEditor((s) => s.current);
  const focusNode = useEditor((s) => s.focusNode);
  const inCurrent = current !== null && scriptNameOfFile(diag.file) === current;
  const located = inCurrent && nodeId !== null;
  return (
    <button
      disabled={!located}
      onClick={() => nodeId !== null && focusNode(nodeId)}
      className={`w-full rounded-md px-2 py-1.5 text-left transition-colors ${
        located ? "hover:bg-white/[0.04]" : "cursor-default opacity-45"
      }`}
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
  const diagNode = useEditor((s) => s.diagNode);
  const diags = report?.diags.map((d, i) => ({ d, i })) ?? [];
  const errors = diags.filter((x) => x.d.level === "error");
  const warnings = diags.filter((x) => x.d.level !== "error");

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
      {!report && (
        <div className="px-2 py-1 text-xs text-zinc-600">
          尚无诊断：保存或点击工具栏「检查」运行
        </div>
      )}
      {report && diags.length === 0 && (
        <div className="px-2 py-1 text-xs text-zinc-600">无诊断，全部通过</div>
      )}
      {errors.length > 0 && (
        <div className="mb-2">
          <div className="px-2 py-1 font-mono text-[10px] tracking-widest text-danger">
            ERROR · {errors.length}
          </div>
          {errors.map((x) => (
            <DiagItem key={`e${x.i}`} diag={x.d} nodeId={diagNode[x.i] ?? null} />
          ))}
        </div>
      )}
      {warnings.length > 0 && (
        <div>
          <div className="px-2 py-1 font-mono text-[10px] tracking-widest text-warn">
            WARNING · {warnings.length}
          </div>
          {warnings.map((x) => (
            <DiagItem key={`w${x.i}`} diag={x.d} nodeId={diagNode[x.i] ?? null} />
          ))}
        </div>
      )}
    </Panel>
  );
}
