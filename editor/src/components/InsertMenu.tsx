// 插入菜单：seq 边「+」与工具栏「末尾追加」共用的节点类型选择弹层。
// 指令类型展开二级 head 列表（spec.heads 排除结构头）；jump 为终端节点，仅末尾追加可选。

import { STRUCTURAL_HEADS } from "../../shared/graph";
import {
  makeCond,
  makeDialogue,
  makeInst,
  makeJump,
  makeOptionGroup,
  type Insertable,
} from "../../shared/graph_ops";
import { appendEndNode, insertOnEdgeAt } from "../state/edit";
import { useEditor } from "../state/store";

const KINDS: { kind: string; label: string; hint: string }[] = [
  { kind: "dialogue", label: "对话", hint: "角色台词" },
  { kind: "inst", label: "指令", hint: "选择指令头…" },
  { kind: "option_group", label: "选项组", hint: "默认两个空选项" },
  { kind: "cond", label: "条件", hint: "if / else 分支" },
  { kind: "jump", label: "跳转", hint: "终端节点" },
];

function factory(kind: string, head?: string): Insertable | null {
  switch (kind) {
    case "dialogue":
      return makeDialogue();
    case "inst":
      return head ? makeInst(head) : null;
    case "option_group":
      return makeOptionGroup();
    case "cond":
      return makeCond("true");
    case "jump":
      return makeJump("main_menu");
    default:
      return null;
  }
}

export function InsertMenu() {
  const menu = useEditor((s) => s.insertMenu);
  const openInsertMenu = useEditor((s) => s.openInsertMenu);
  const spec = useEditor((s) => s.spec);
  if (!menu) return null;

  const onEdge = menu.edgeIndex !== null;
  const heads = (spec?.heads ?? []).filter((h) => !STRUCTURAL_HEADS.has(h));

  const pick = (kind: string, head?: string) => {
    const item = factory(kind, head);
    if (!item) return;
    const id = menu.edgeIndex !== null ? insertOnEdgeAt(menu.edgeIndex, item) : appendEndNode(item);
    if (id !== null) openInsertMenu(null);
  };

  const itemCls =
    "w-full rounded-md px-2 py-1.5 text-left text-xs text-ink transition-colors hover:bg-grid/50 hover:text-accent disabled:cursor-not-allowed disabled:opacity-35";

  return (
    <>
      <div className="fixed inset-0 z-40" onClick={() => openInsertMenu(null)} />
      <div
        className="fixed z-50 max-h-80 w-52 overflow-y-auto rounded-md border border-grid bg-panel p-1.5"
        style={{
          left: Math.min(menu.x, window.innerWidth - 224),
          top: Math.min(menu.y, window.innerHeight - 340),
        }}
      >
        <div className="px-2 pt-1 pb-1.5 font-mono text-[10px] tracking-widest text-mut uppercase">
          {onEdge ? "在边上插入" : "末尾追加"}
        </div>
        {KINDS.map((k) =>
          k.kind === "inst" ? (
            <details key={k.kind} className="group">
              <summary
                className={`${itemCls} flex cursor-pointer list-none items-center justify-between`}
              >
                <span>{k.label}</span>
                <span className="font-mono text-[10px] text-dim">{k.hint}</span>
              </summary>
              <div className="mt-0.5 ml-2 max-h-44 overflow-y-auto border-l border-grid pl-1">
                {heads.map((h) => (
                  <button
                    key={h}
                    onClick={() => pick("inst", h)}
                    className="w-full rounded px-1.5 py-1 text-left font-mono text-[11px] text-mut hover:bg-grid/50 hover:text-accent"
                  >
                    {h}
                  </button>
                ))}
              </div>
            </details>
          ) : (
            <button
              key={k.kind}
              disabled={k.kind === "jump" && onEdge}
              title={k.kind === "jump" && onEdge ? "jump 是终端节点，仅可末尾追加" : k.hint}
              onClick={() => pick(k.kind)}
              className={`${itemCls} flex items-center justify-between`}
            >
              <span>{k.label}</span>
              <span className="font-mono text-[10px] text-dim">{k.hint}</span>
            </button>
          ),
        )}
      </div>
    </>
  );
}
