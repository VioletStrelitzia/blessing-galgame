// 对话 prev/post 指令槽编辑器：每行 = head 选择器 + 紧凑参数行 + 删除；底部「添加指令」。
// head 候选 = spec.heads 排除结构头（与引擎 _STRUCTURAL_PARAMS 同源）。

import { STRUCTURAL_HEADS, type InstPayload } from "../../shared/graph";
import type { InstObj } from "../../shared/graph_ops";
import { patchSlot } from "../state/edit";
import { useEditor } from "../state/store";
import { SelectInput, SmallButton } from "../components/controls";
import { InstParamsForm } from "./InstParamsForm";

export function SlotEditor({
  dialogueId,
  slot,
  list,
}: {
  dialogueId: string;
  slot: "prev" | "post";
  list: InstPayload[];
}) {
  const spec = useEditor((s) => s.spec);
  const heads = (spec?.heads ?? []).filter((h) => !STRUCTURAL_HEADS.has(h));
  const commit = (next: InstObj[]) => patchSlot(dialogueId, slot, next);

  return (
    <div className="flex flex-col gap-1.5 px-2 pb-1">
      {list.map((inst, i) => (
        <div key={i} className="rounded-md border border-grid bg-panel py-1.5">
          <div className="mb-1 flex items-center gap-1 px-2">
            <span className="font-mono text-[10px] text-dim">{slot === "prev" ? "<" : ">"}</span>
            <SelectInput
              mono
              className="min-w-0 flex-1"
              value={inst.head}
              options={heads.includes(inst.head) ? heads : [inst.head, ...heads]}
              onChange={(h) => commit(list.map((x, j) => (j === i ? { head: h, params: {} } : x)))}
            />
            <SmallButton
              danger
              title="删除该指令"
              onClick={() => commit(list.filter((_, j) => j !== i))}
            >
              ×
            </SmallButton>
          </div>
          <InstParamsForm
            head={inst.head}
            params={inst.params}
            onChange={(params) =>
              commit(list.map((x, j) => (j === i ? { head: inst.head, params } : x)))
            }
          />
        </div>
      ))}
      <div>
        <SmallButton onClick={() => commit([...list, { head: heads[0] ?? "WAIT", params: {} }])}>
          ＋ 添加指令
        </SmallButton>
      </div>
    </div>
  );
}
