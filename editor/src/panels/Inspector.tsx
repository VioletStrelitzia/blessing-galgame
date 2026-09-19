// 可编辑属性面板（spec 驱动）：dialogue 角色/台词/锚点/前后指令槽；inst 参数表单；
// option_group/cond 分支编辑器；jump 目标（剧本 datalist）；comment 多行文本。

import type { GraphNode } from "../../shared/graph";
import {
  patchComment,
  patchDialogue,
  patchInstParams,
  patchJump,
  removeNodeById,
} from "../state/edit";
import { useEditor } from "../state/store";
import { Datalist, Field, SmallButton, TextArea, TextInput } from "../components/controls";
import { CondEditor, OptionsEditor } from "./BranchEditors";
import { InstParamsForm } from "./InstParamsForm";
import { Panel } from "./Panel";
import { SlotEditor } from "./SlotEditor";

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-3">
      <div className="px-2 pt-2 pb-1 font-mono text-[10px] tracking-widest text-zinc-500 uppercase">
        {title}
      </div>
      {children}
    </div>
  );
}

function DeleteButton({ node }: { node: GraphNode }) {
  if (node.kind === "start" || node.kind === "end") return null;
  return (
    <div className="mt-4 border-t border-white/8 px-2 pt-3">
      <SmallButton
        danger
        title="删除节点（Delete / Backspace）"
        onClick={() => removeNodeById(node.id)}
      >
        删除节点
      </SmallButton>
    </div>
  );
}

function DialogueView({ node }: { node: GraphNode & { kind: "dialogue" } }) {
  return (
    <>
      <Section title="对话">
        <Field label="角色">
          <TextInput
            value={node.character}
            placeholder="（旁白）"
            onChange={(v) => patchDialogue(node.id, { character: v })}
          />
        </Field>
        <Field label="台词">
          <TextArea
            mono
            rows={5}
            value={node.text}
            onChange={(v) => patchDialogue(node.id, { text: v })}
          />
        </Field>
        {node.anchors.length > 0 && (
          <div className="flex flex-wrap gap-1 px-2 pb-1">
            {node.anchors.map((a, i) => (
              <span
                key={i}
                className="rounded border border-white/10 bg-white/[0.04] px-1 font-mono text-[10px] leading-4 text-zinc-500"
                title="锚点为文本派生信息，修改台词后由引擎重建"
              >
                @{a.index} {a.head}
              </span>
            ))}
          </div>
        )}
      </Section>
      <Section title={`前指令 · ${node.prev.length}`}>
        <SlotEditor dialogueId={node.id} slot="prev" list={node.prev} />
      </Section>
      <Section title={`后指令 · ${node.post.length}`}>
        <SlotEditor dialogueId={node.id} slot="post" list={node.post} />
      </Section>
    </>
  );
}

function NodeView({ node }: { node: GraphNode }) {
  const scripts = useEditor((s) => s.scripts);

  if (node.kind === "dialogue") return <DialogueView node={node} />;

  if (node.kind === "inst") {
    return (
      <Section title="指令">
        <div className="mb-2 px-2 font-mono text-xs text-accent">{node.head}</div>
        <InstParamsForm
          head={node.head}
          params={node.params}
          onChange={(params) => patchInstParams(node.id, params)}
        />
      </Section>
    );
  }

  if (node.kind === "jump") {
    return (
      <Section title="跳转">
        <Field label="target">
          <TextInput
            mono
            value={node.target}
            list="jump-targets"
            onChange={(v) => patchJump(node.id, v)}
          />
          <Datalist id="jump-targets" options={[...scripts, "main_menu"]} />
        </Field>
      </Section>
    );
  }

  if (node.kind === "option_group") {
    return (
      <Section title="选项">
        <OptionsEditor nodeId={node.id} />
      </Section>
    );
  }

  if (node.kind === "cond") {
    return (
      <Section title="分支">
        <CondEditor nodeId={node.id} />
      </Section>
    );
  }

  if (node.kind === "comment") {
    return (
      <Section title="注释">
        <Field label="text">
          <TextArea mono rows={4} value={node.text} onChange={(v) => patchComment(node.id, v)} />
        </Field>
        <div className="px-2 font-mono text-[10px] text-zinc-600">
          before: {node.before ?? "（文件头）"}
        </div>
      </Section>
    );
  }

  return (
    <Section title="节点">
      <div className="px-2 py-1 font-mono text-xs text-zinc-500">{node.kind}（不可编辑）</div>
    </Section>
  );
}

export function Inspector() {
  const graph = useEditor((s) => s.graph);
  const selected = useEditor((s) => s.selected);
  const node = graph?.nodes.find((n) => n.id === selected);

  return (
    <Panel title="属性" className="h-full">
      {!node && <div className="px-2 py-1 text-xs text-zinc-600">点击画布节点查看属性</div>}
      {node && (
        <>
          <div className="px-2 pt-2 font-mono text-[10px] text-zinc-600">id: {node.id}</div>
          <NodeView node={node} />
          <DeleteButton node={node} />
        </>
      )}
    </Panel>
  );
}
