// 编辑动作层：每个 action = 调 shared/graph_ops 纯函数（经 store.mutateGraph 压撤销快照 + dirty）。
// 文本类输入带 tag，逐键变更在 800ms 窗口内合并为一个撤销步。

import type { GraphEdge, Params } from "../../shared/graph";
import * as ops from "../../shared/graph_ops";
import type { Insertable, InstObj } from "../../shared/graph_ops";
import { useEditor } from "./store";

/** seq 边插入节点；返回新节点 id（领域校验失败返回 null 并置 error）。成功后选中并滚入视野 */
export function insertOnEdgeAt(edgeIndex: number, item: Insertable): string | null {
  const ids = useEditor.getState().mutateGraph((g) => ops.insertOnEdge(g, edgeIndex, item), {
    selectNew: true,
  });
  return reveal(ids);
}

/** 末尾追加节点（appendEnd 口径）；返回新节点 id。成功后选中并滚入视野 */
export function appendEndNode(item: Insertable): string | null {
  const ids = useEditor.getState().mutateGraph((g) => ops.appendEnd(g, item), { selectNew: true });
  return reveal(ids);
}

/** 新节点选中 + focusReq（FlowCanvas 据此 setCenter 滚入视野） */
function reveal(ids: string[] | null): string | null {
  const id = ids?.[0] ?? null;
  if (id !== null) useEditor.getState().focusNode(id);
  return id;
}

/** 新增注释便签：有选中节点（start/end/comment 除外）则附着其上，否则 before=null（文件头） */
export function addCommentAt(): string | null {
  const s = useEditor.getState();
  const sel = s.graph?.nodes.find((n) => n.id === s.selected);
  const before =
    sel && sel.kind !== "comment" && sel.kind !== "start" && sel.kind !== "end" ? sel.id : null;
  const ids = s.mutateGraph((g) => ops.addComment(g, before, ""), { selectNew: true });
  return reveal(ids);
}

export function removeNodeById(id: string): void {
  useEditor.getState().mutateGraph((g) => ops.removeNode(g, id));
  const s = useEditor.getState();
  if (s.selected === id) s.select(null);
}

export function patchDialogue(id: string, patch: { character?: string; text?: string }): void {
  useEditor.getState().mutateGraph((g) => ops.updateDialogue(g, id, patch), {
    tag: `dlg:${id}:${patch.character !== undefined ? "c" : "t"}`,
  });
}

export function patchInstParams(id: string, params: Params): void {
  useEditor.getState().mutateGraph((g) => ops.updateInstParams(g, id, params));
}

export function patchSlot(dialogueId: string, slot: "prev" | "post", list: InstObj[]): void {
  useEditor.getState().mutateGraph((g) => ops.setSlot(g, dialogueId, slot, list));
}

export function patchJump(id: string, target: string): void {
  useEditor.getState().mutateGraph((g) => ops.updateJump(g, id, target), { tag: `jump:${id}` });
}

export function patchComment(id: string, text: string): void {
  useEditor.getState().mutateGraph((g) => ops.updateComment(g, id, text), { tag: `cmt:${id}` });
}

/** 组的某类分支出边（数组序 = 分支序），附 edges 下标 */
export function branchRows(
  groupId: string,
  kind: "option" | "branch",
): { edge: GraphEdge; edgeIndex: number }[] {
  const graph = useEditor.getState().graph;
  if (!graph) return [];
  return graph.edges
    .map((edge, edgeIndex) => ({ edge, edgeIndex }))
    .filter(({ edge }) => edge.from === groupId && edge.kind === kind);
}

export function optionAdd(groupId: string): void {
  const n = branchRows(groupId, "option").length;
  useEditor.getState().mutateGraph((g) => ops.addOption(g, groupId, { text: `选项 ${n + 1}` }));
}

export function optionUpdate(
  groupId: string,
  edgeIndex: number,
  patch: { text?: string; cond?: string | null },
): void {
  useEditor.getState().mutateGraph((g) => ops.updateOption(g, groupId, edgeIndex, patch), {
    tag: `opt:${edgeIndex}:${patch.text !== undefined ? "t" : "c"}`,
  });
}

export function optionRemove(groupId: string, edgeIndex: number): void {
  useEditor.getState().mutateGraph((g) => ops.removeOption(g, groupId, edgeIndex));
}

export function optionMove(groupId: string, edgeIndex: number, dir: -1 | 1): void {
  useEditor.getState().mutateGraph((g) => ops.moveOption(g, groupId, edgeIndex, dir));
}

export function branchAdd(condId: string): void {
  useEditor.getState().mutateGraph((g) => ops.addBranch(g, condId, "true"));
}

export function branchUpdate(condId: string, edgeIndex: number, cond: string): void {
  useEditor
    .getState()
    .mutateGraph((g) => ops.updateBranch(g, condId, edgeIndex, cond), { tag: `br:${edgeIndex}` });
}

export function branchRemove(condId: string, edgeIndex: number): void {
  useEditor.getState().mutateGraph((g) => ops.removeBranch(g, condId, edgeIndex));
}
