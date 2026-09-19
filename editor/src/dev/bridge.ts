// 调试桥客户端（src/dev/bridge.ts）：启动时 GET /api/dev/enabled，启用则
// new EventSource("/api/dev/events") 收 SSE command → 注册表执行 → POST /api/dev/result。
// 供自动化/外部脚本经 /api/dev/command 驱动编辑器（curl 示例见 README）。

import type { GraphEdge, GraphNode } from "../../shared/graph";
import {
  makeCond,
  makeDialogue,
  makeInst,
  makeJump,
  makeOptionGroup,
} from "../../shared/graph_ops";
import { api } from "../api";
import { appendEndNode, removeNodeById } from "../state/edit";
import { openScript, runCheck, save, verify } from "../state/io";
import { useEditor } from "../state/store";

type Args = Record<string, unknown>;
type Handler = (args: Args) => unknown | Promise<unknown>;

interface CommandDef {
  /** 参数签名（list_commands 自描述用），如 "{selector,value}" */
  sig: string;
  run: Handler;
}

/** state 命令的节点标签：dialogue 文本前 20 字、inst head、jump target、选项组首选项文本，其余 kind */
export function nodeLabel(node: GraphNode, edges: GraphEdge[]): string {
  switch (node.kind) {
    case "dialogue":
      return node.text.slice(0, 20);
    case "inst":
      return node.head;
    case "jump":
      return node.target;
    case "option_group":
      return edges.find((e) => e.from === node.id && e.kind === "option")?.text ?? node.kind;
    default:
      return node.kind;
  }
}

function requireSelector(selector: unknown): Element {
  const el = document.querySelector(String(selector));
  if (!el) throw new Error(`选择器无匹配元素: ${String(selector)}`);
  return el;
}

/** 原生 setter 写值 + input/change 事件（React 受控输入可感知） */
function fillElement(el: Element, value: unknown): void {
  const proto =
    el instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : el instanceof HTMLSelectElement
        ? HTMLSelectElement.prototype
        : el instanceof HTMLInputElement
          ? HTMLInputElement.prototype
          : null;
  if (!proto) throw new Error("目标元素不是 input/textarea/select");
  Object.getOwnPropertyDescriptor(proto, "value")?.set?.call(el, String(value ?? ""));
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
}

/** IO 动作吞错（置 store.error），桥接层据以回报 ok:false */
async function runIO(fn: () => Promise<void>): Promise<{ dirty: boolean; error: null }> {
  await fn();
  const err = useEditor.getState().error;
  if (err !== null) throw new Error(err);
  return { dirty: useEditor.getState().dirty, error: null };
}

function diagCounts(): { error: number; warning: number } {
  let error = 0;
  let warning = 0;
  for (const c of Object.values(useEditor.getState().nodeDiags)) {
    error += c.error;
    warning += c.warning;
  }
  return { error, warning };
}

function addNode({ kind, head }: Args): { id: string } {
  const item = (() => {
    switch (String(kind)) {
      case "dialogue":
        return makeDialogue();
      case "inst":
        if (typeof head !== "string" || head === "") throw new Error("add_node: inst 需要 head");
        return makeInst(head);
      case "option":
      case "option_group":
        return makeOptionGroup();
      case "cond":
        return makeCond("true");
      case "jump":
        return makeJump("main_menu");
      default:
        throw new Error(`add_node: 未知 kind ${String(kind)}`);
    }
  })();
  const id = appendEndNode(item);
  if (id === null) throw new Error(useEditor.getState().error ?? "add_node 失败");
  return { id };
}

const registry: Record<string, CommandDef> = {
  ping: { sig: "{}", run: () => "pong" },
  state: {
    sig: "{}",
    run: () => {
      const s = useEditor.getState();
      return {
        script: s.current,
        nodeCount: s.graph?.nodes.length ?? 0,
        edgeCount: s.graph?.edges.length ?? 0,
        selectedId: s.selected,
        dirty: s.dirty,
        diagCounts: diagCounts(),
        nodes: (s.graph?.nodes ?? []).map((n) => ({
          id: n.id,
          kind: n.kind,
          label: nodeLabel(n, s.graph?.edges ?? []),
        })),
      };
    },
  },
  click: {
    sig: "{selector}",
    run: ({ selector }) => (requireSelector(selector) as HTMLElement).click(),
  },
  fill: {
    sig: "{selector,value}",
    run: ({ selector, value }) => fillElement(requireSelector(selector), value),
  },
  select_script: {
    sig: "{script}",
    run: async ({ script }) => {
      await openScript(String(script));
      if (useEditor.getState().current !== String(script))
        throw new Error(`剧本打开失败: ${String(script)}`);
    },
  },
  select_node: {
    sig: "{id}",
    run: ({ id }) => {
      const s = useEditor.getState();
      if (!s.graph?.nodes.some((n) => n.id === String(id)))
        throw new Error(`节点不存在: ${String(id)}`);
      s.focusNode(String(id));
    },
  },
  save: { sig: "{}", run: () => runIO(save) },
  check: { sig: "{}", run: () => runIO(runCheck) },
  verify: { sig: "{}", run: () => runIO(verify) },
  undo: { sig: "{}", run: () => useEditor.getState().undo() },
  redo: { sig: "{}", run: () => useEditor.getState().redo() },
  add_node: { sig: "{kind,head?}  kind: dialogue|inst|option_group|cond|jump", run: addNode },
  delete_selected: {
    sig: "{}",
    run: () => {
      const s = useEditor.getState();
      if (s.selected === null) throw new Error("无选中节点");
      removeNodeById(s.selected);
    },
  },
  key: {
    sig: "{key,ctrl?,shift?}",
    run: ({ key, ctrl, shift }) => {
      document.dispatchEvent(
        new KeyboardEvent("keydown", {
          key: String(key),
          ctrlKey: ctrl === true,
          shiftKey: shift === true,
          bubbles: true,
        }),
      );
    },
  },
  list_commands: {
    sig: "{}",
    run: () => Object.entries(registry).map(([action, def]) => ({ action, params: def.sig })),
  },
};

async function handle(msg: { id: string; action: string; args: Args | null }): Promise<void> {
  try {
    const def = registry[msg.action];
    if (!def) throw new Error(`未知调试命令: ${msg.action}`);
    const data = (await def.run(msg.args ?? {})) ?? null;
    await api.devResult(msg.id, true, data);
  } catch (e) {
    await api.devResult(msg.id, false, (e as Error).message);
  }
}

let started = false;

/** 入口：/api/dev/enabled 为 true 时建立 SSE；否则静默退出（生产/非 dev 服务） */
export async function startDevBridge(): Promise<void> {
  if (started) return;
  started = true;
  try {
    const { enabled } = await api.devEnabled();
    if (!enabled) return;
  } catch {
    return;
  }
  const es = new EventSource("/api/dev/events");
  es.addEventListener("command", (ev) => {
    void handle(JSON.parse((ev as MessageEvent).data as string));
  });
}
