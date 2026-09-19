// 回环校验横幅（顶栏下方）：绿色「图文一致」/ 红色 diffs 列表，可关闭。

import { useEditor } from "../state/store";

export function VerifyBanner() {
  const result = useEditor((s) => s.verifyResult);
  const dismiss = useEditor((s) => s.dismissVerify);
  if (!result) return null;

  if (result.equal) {
    return (
      <div className="flex shrink-0 items-center gap-2 border-b border-accent/25 bg-accent/[0.07] px-4 py-1.5">
        <span className="font-mono text-xs text-accent">✓ 图文一致</span>
        <span className="font-mono text-[10px] text-mut">
          {new Date(result.at).toLocaleTimeString()} · 画布图与引擎回读图语义等价
        </span>
        <div className="flex-1" />
        <button onClick={dismiss} className="font-mono text-xs text-mut hover:text-ink">
          ×
        </button>
      </div>
    );
  }
  return (
    <div className="shrink-0 border-b border-danger/30 bg-danger/[0.08] px-4 py-1.5">
      <div className="flex items-center gap-2">
        <span className="font-mono text-xs text-danger">
          ✗ 图文不一致 · {result.diffs.length} 处差异
        </span>
        <div className="flex-1" />
        <button onClick={dismiss} className="font-mono text-xs text-mut hover:text-ink">
          ×
        </button>
      </div>
      <ul className="mt-1 max-h-28 overflow-y-auto">
        {result.diffs.map((d, i) => (
          <li key={i} className="font-mono text-[11px] leading-5 text-danger/90">
            {d}
          </li>
        ))}
      </ul>
    </div>
  );
}
