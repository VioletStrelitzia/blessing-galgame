// 行内编辑共用机制（双击进入）：草稿态本地保存，提交才走 store action（与 Inspector 同源）。
// 键位约定（纯函数 resolveInlineKey，单测覆盖）：Enter 提交、Shift+Enter 换行（textarea 默认行为）、
// Esc 取消还原（草稿从未入库，丢弃即还原）；失焦提交（容器外 relatedTarget 判定，字段间 Tab 不触发）。

import { useCallback, useEffect, useRef, useState } from "react";

export type InlineKeyAction = "submit" | "cancel" | null;

export function resolveInlineKey(key: string, shiftKey: boolean): InlineKeyAction {
  if (key === "Escape") return "cancel";
  if (key === "Enter" && !shiftKey) return "submit";
  return null;
}

export interface InlineEdit<T extends object> {
  editing: boolean;
  draft: T | null;
  /** 读取当前值进入编辑态 */
  start(): void;
  setDraft(patch: Partial<T>): void;
  /** 有实际变更才 commit（避免空撤销步）；随后退出编辑态 */
  submit(): void;
  cancel(): void;
}

export function useInlineEdit<T extends object>(
  current: T,
  commit: (draft: T) => void,
): InlineEdit<T> {
  const [draft, setDraftState] = useState<T | null>(null);
  const draftRef = useRef(draft);
  const currentRef = useRef(current);
  const commitRef = useRef(commit);
  // 每次渲染后同步最新值（react-hooks/refs 禁渲染期写 ref）
  useEffect(() => {
    draftRef.current = draft;
    currentRef.current = current;
    commitRef.current = commit;
  });

  const start = useCallback(() => setDraftState({ ...currentRef.current }), []);
  const cancel = useCallback(() => setDraftState(null), []);
  const submit = useCallback(() => {
    const d = draftRef.current;
    if (d === null) return;
    const changed = (Object.keys(d) as (keyof T)[]).some((k) => d[k] !== currentRef.current[k]);
    if (changed) commitRef.current(d);
    setDraftState(null);
  }, []);
  const setDraft = useCallback((patch: Partial<T>) => {
    setDraftState((d) => (d === null ? d : { ...d, ...patch }));
  }, []);

  return { editing: draft !== null, draft, start, cancel, submit, setDraft };
}
