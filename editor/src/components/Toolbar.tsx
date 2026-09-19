// 画布上方工具栏：末尾追加（InsertMenu 弹出）、新建剧本、保存（Ctrl+S）、撤销/重做、检查、回环校验。

import { useRef, useState } from "react";
import { addCommentAt } from "../state/edit";
import { newScript, runCheck, save, verify } from "../state/io";
import { useEditor } from "../state/store";

const btn =
  "rounded-md border border-grid bg-base px-2 py-1 font-mono text-[11px] text-ink transition-colors hover:border-accent/40 hover:text-accent disabled:cursor-not-allowed disabled:opacity-35";

function NewScriptButton() {
  const mode = useEditor((s) => s.mode);
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const disabled = mode === "fixtures";

  const commit = () => {
    const n = name.trim();
    if (n) void newScript(n);
    setOpen(false);
    setName("");
  };

  if (!open) {
    return (
      <button
        className={btn}
        disabled={disabled}
        title={disabled ? "fixtures 模式为只读，不支持新建剧本" : "新建剧本"}
        onClick={() => {
          setOpen(true);
          setTimeout(() => inputRef.current?.focus(), 0);
        }}
      >
        新建剧本
      </button>
    );
  }
  return (
    <span className="flex items-center gap-1">
      <input
        ref={inputRef}
        value={name}
        placeholder="script_name"
        onChange={(e) => setName(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") setOpen(false);
        }}
        onBlur={() => setOpen(false)}
        className="w-36 rounded-md border border-accent/40 bg-base px-2 py-1 font-mono text-[11px] text-ink outline-none placeholder:text-dim"
      />
      <button className={btn} onMouseDown={(e) => e.preventDefault()} onClick={commit}>
        创建
      </button>
    </span>
  );
}

export function Toolbar() {
  const openInsertMenu = useEditor((s) => s.openInsertMenu);
  const insertMenu = useEditor((s) => s.insertMenu);
  const graph = useEditor((s) => s.graph);
  const dirty = useEditor((s) => s.dirty);
  const saving = useEditor((s) => s.saving);
  const checking = useEditor((s) => s.checking);
  const verifying = useEditor((s) => s.verifying);
  const mode = useEditor((s) => s.mode);
  const canUndo = useEditor((s) => s.undoStack.length > 0);
  const canRedo = useEditor((s) => s.redoStack.length > 0);
  const undo = useEditor((s) => s.undo);
  const redo = useEditor((s) => s.redo);

  const hasGraph = graph !== null;
  return (
    <div className="flex h-9 shrink-0 items-center gap-1.5 border-b border-grid px-2">
      <button
        className={`${btn} border-accent/40 text-accent`}
        disabled={!hasGraph}
        title="在末尾追加节点"
        onClick={(e) => {
          if (insertMenu) openInsertMenu(null);
          else openInsertMenu({ edgeIndex: null, x: e.clientX, y: e.clientY });
        }}
      >
        ＋ 追加
      </button>
      <NewScriptButton />
      <button
        className={btn}
        disabled={!hasGraph}
        title="添加注释便签（有选中节点时附着其上，否则置于文件头）"
        onClick={() => addCommentAt()}
      >
        ＃ 注释
      </button>
      <span className="mx-1 h-4 w-px bg-grid" />
      <button
        className={btn}
        disabled={!hasGraph || saving}
        title="保存（Ctrl+S）：发射文本 + sidecar 并自动检查"
        onClick={() => void save()}
      >
        {saving ? "保存中…" : "保存"}
      </button>
      <button className={btn} disabled={!canUndo} title="撤销（Ctrl+Z）" onClick={undo}>
        撤销
      </button>
      <button className={btn} disabled={!canRedo} title="重做（Ctrl+Shift+Z）" onClick={redo}>
        重做
      </button>
      <span className="mx-1 h-4 w-px bg-grid" />
      <button
        className={btn}
        disabled={!hasGraph || checking}
        title="对全部剧本运行编译期检查"
        onClick={() => void runCheck()}
      >
        {checking ? "检查中…" : "检查"}
      </button>
      <button
        className={btn}
        disabled={!hasGraph || verifying || mode === "fixtures"}
        title={
          mode === "fixtures"
            ? "fixtures 模式无引擎可回读，回环校验不可用"
            : "重新 dump 服务端图并与画布图做语义对比"
        }
        onClick={() => void verify()}
      >
        {verifying ? "校验中…" : "回环校验"}
      </button>
      <div className="flex-1" />
      {dirty && <span className="h-2 w-2 rounded-full bg-warn" title="有未保存的修改" />}
    </div>
  );
}
