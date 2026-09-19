// 选项组 / 条件链的分支编辑：选项行（text + cond + ↑↓ + 删除）、elif/else 分支行（cond + 删除）。
// 分支序 = 该节点出边在 edges 数组中的相对顺序；删除最后一条选项会内联展开整个组。

import { useEditor } from "../state/store";
import {
  branchAdd,
  branchRemove,
  branchRows,
  branchUpdate,
  optionAdd,
  optionMove,
  optionRemove,
  optionUpdate,
} from "../state/edit";
import { SmallButton, TextInput } from "../components/controls";

export function OptionsEditor({ nodeId }: { nodeId: string }) {
  useEditor((s) => s.graph); // 订阅图变化以刷新行
  const rows = branchRows(nodeId, "option");
  return (
    <div className="flex flex-col gap-1.5 px-2 pb-1">
      {rows.map(({ edge, edgeIndex }, i) => (
        <div key={edgeIndex} className="flex items-center gap-1">
          <span className="font-mono text-[10px] text-accent">*</span>
          <TextInput
            value={edge.text ?? ""}
            placeholder="选项文本"
            onChange={(v) => optionUpdate(nodeId, edgeIndex, { text: v })}
          />
          <span className="w-24 shrink-0">
            <TextInput
              mono
              value={edge.cond ?? ""}
              placeholder="if:条件"
              onChange={(v) => optionUpdate(nodeId, edgeIndex, { cond: v })}
            />
          </span>
          <SmallButton
            title="上移"
            disabled={i === 0}
            onClick={() => optionMove(nodeId, edgeIndex, -1)}
          >
            ↑
          </SmallButton>
          <SmallButton
            title="下移"
            disabled={i === rows.length - 1}
            onClick={() => optionMove(nodeId, edgeIndex, 1)}
          >
            ↓
          </SmallButton>
          <SmallButton
            danger
            title={rows.length === 1 ? "删除最后一条选项将内联展开整个组" : "删除该选项"}
            onClick={() => optionRemove(nodeId, edgeIndex)}
          >
            ×
          </SmallButton>
        </div>
      ))}
      <div>
        <SmallButton onClick={() => optionAdd(nodeId)}>＋ 添加选项</SmallButton>
      </div>
    </div>
  );
}

export function CondEditor({ nodeId }: { nodeId: string }) {
  useEditor((s) => s.graph);
  const rows = branchRows(nodeId, "branch");
  return (
    <div className="flex flex-col gap-1.5 px-2 pb-1">
      {rows.map(({ edge, edgeIndex }, i) => {
        const isElse = edge.cond === undefined;
        const kw = i === 0 ? "if" : isElse ? "else" : "elif";
        return (
          <div key={edgeIndex} className="flex items-center gap-1">
            <span className="w-8 shrink-0 text-right font-mono text-[10px] text-accent">{kw}</span>
            {isElse ? (
              <span className="flex-1 rounded-md border border-grid/60 bg-panel px-2 py-1 font-mono text-xs text-dim">
                else（无条件）
              </span>
            ) : (
              <TextInput
                mono
                value={edge.cond ?? ""}
                placeholder="条件表达式"
                onChange={(v) => branchUpdate(nodeId, edgeIndex, v)}
              />
            )}
            <SmallButton
              danger
              disabled={rows.length <= 1}
              title={rows.length <= 1 ? "条件链至少保留一条分支" : "删除该分支"}
              onClick={() => branchRemove(nodeId, edgeIndex)}
            >
              ×
            </SmallButton>
          </div>
        );
      })}
      <div>
        <SmallButton onClick={() => branchAdd(nodeId)}>＋ 添加 elif</SmallButton>
      </div>
    </div>
  );
}
