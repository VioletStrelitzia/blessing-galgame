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
import { openScript, showDetail } from "../state/io";
import { Datalist, Field, SmallButton, TextArea, TextInput } from "../components/controls";
import { CondEditor, OptionsEditor } from "./BranchEditors";
import { InstParamsForm } from "./InstParamsForm";
import { Panel } from "./Panel";
import { SlotEditor } from "./SlotEditor";

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-3">
      <div className="px-2 pt-2 pb-1 font-mono text-[10px] tracking-widest text-mut uppercase">
        {title}
      </div>
      {children}
    </div>
  );
}

function DeleteButton({ node }: { node: GraphNode }) {
  if (node.kind === "start" || node.kind === "end") return null;
  return (
    <div className="mt-4 border-t border-grid px-2 pt-3">
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
                className="rounded border border-grid bg-grid/40 px-1 font-mono text-[10px] leading-4 text-mut"
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
        <div className="px-2 font-mono text-[10px] text-dim">
          before: {node.before ?? "（文件头）"}
        </div>
      </Section>
    );
  }

  return (
    <Section title="节点">
      <div className="px-2 py-1 font-mono text-xs text-mut">{node.kind}（不可编辑）</div>
    </Section>
  );
}

/** 总览视图：选中剧本节点的完整统计 + 打开入口 */
function OverviewInspector() {
  const overview = useEditor((s) => s.overview);
  const selected = useEditor((s) => s.overviewSelected);
  const script = overview?.scripts.find((s) => s.name === selected);

  return (
    <Panel title="剧本" className="h-full">
      {!script && (
        <div className="px-2 py-1 text-xs text-dim">
          {selected === null ? "点击总览节点查看统计" : "终态/幽灵节点无统计"}
        </div>
      )}
      {script && (
        <>
          <div className="px-2 pt-2 font-mono text-xs font-semibold text-accent">
            {script.name}
            {overview?.begin === script.name && (
              <span className="ml-2 font-mono text-[10px] text-ok">BEGIN</span>
            )}
          </div>
          <div className="mt-2 flex flex-col gap-1 px-2">
            {(
              [
                ["对话", script.dialogues],
                ["指令", script.insts],
                ["选项", script.options],
                ["分支", script.conds],
                ["跳转", script.jumps],
              ] as const
            ).map(([label, n]) => (
              <div key={label} className="flex justify-between font-mono text-xs">
                <span className="text-mut">{label}</span>
                <span className="text-ink">{n}</span>
              </div>
            ))}
          </div>
          <div className="mt-4 border-t border-grid px-2 pt-3">
            <SmallButton
              title="打开剧本（双击节点亦可）"
              onClick={() => {
                showDetail();
                void openScript(script.name);
              }}
            >
              打开剧本 →
            </SmallButton>
          </div>
        </>
      )}
    </Panel>
  );
}

export function Inspector() {
  const graph = useEditor((s) => s.graph);
  const selected = useEditor((s) => s.selected);
  const view = useEditor((s) => s.view);
  const node = graph?.nodes.find((n) => n.id === selected);

  if (view === "overview") return <OverviewInspector />;

  return (
    <Panel title="属性" className="h-full">
      {!node && <div className="px-2 py-1 text-xs text-dim">点击画布节点查看属性</div>}
      {node && (
        <>
          <div className="px-2 pt-2 font-mono text-[10px] text-dim">id: {node.id}</div>
          <NodeView node={node} />
          <DeleteButton node={node} />
        </>
      )}
    </Panel>
  );
}
