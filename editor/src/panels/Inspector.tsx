// spec 驱动的只读属性面板：inst 按 spec.json 参数序展示（结构字段隐藏）；
// dialogue 展示原文/显示文本/锚点/prev/post（指令经 emitInst 还原为文本形态）。

import { emitInst } from "../../shared/emit";
import type { GraphNode, InstPayload } from "../../shared/graph";
import { useEditor } from "../store";
import { Panel } from "./Panel";

function Row({ name, value, dim }: { name: string; value: string; dim?: boolean }) {
  return (
    <div className="grid grid-cols-[96px_1fr] gap-2 px-2 py-1 text-xs">
      <span className="font-mono text-zinc-500">{name}</span>
      <span className={`font-mono break-all ${dim ? "text-zinc-600" : "text-zinc-200"}`}>
        {value}
      </span>
    </div>
  );
}

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

function InstView({ inst }: { inst: InstPayload }) {
  const spec = useEditor((s) => s.spec);
  const params = spec?.spec[inst.head] ?? [];
  const visible = params.filter((p) => !p.structural);
  return (
    <>
      {visible.map((p) => {
        const v = inst.params[p.name];
        return (
          <Row
            key={p.name}
            name={p.name}
            value={v === undefined ? `${fmtDefault(p.default)}（默认）` : String(v)}
            dim={v === undefined}
          />
        );
      })}
      {visible.length === 0 && <div className="px-2 py-1 text-xs text-zinc-600">无参数</div>}
    </>
  );
}

function fmtDefault(d: unknown): string {
  return typeof d === "string" || typeof d === "number" || typeof d === "boolean"
    ? String(d)
    : "[]";
}

function ParamMeta({ head }: { head: string }) {
  const spec = useEditor((s) => s.spec);
  const params = spec?.spec[head] ?? [];
  return (
    <div className="px-2 py-1 font-mono text-[10px] leading-relaxed text-zinc-600">
      {params
        .filter((p) => !p.structural)
        .map((p) => `${p.name}: ${p.type}${p.role ? ` · ${p.role}` : ""}`)
        .join("\n")}
    </div>
  );
}

function NodeView({ node }: { node: GraphNode }) {
  const graph = useEditor((s) => s.graph);
  const spec = useEditor((s) => s.spec);

  if (node.kind === "dialogue") {
    return (
      <>
        <Section title="对话">
          <Row name="角色" value={node.character || "（旁白）"} dim={!node.character} />
          <div className="px-2 py-1 font-mono text-xs leading-relaxed break-all whitespace-pre-wrap text-zinc-200">
            {node.text}
          </div>
          {node.display_text !== node.text && (
            <div className="px-2 py-1 text-xs leading-relaxed break-all whitespace-pre-wrap text-zinc-400">
              {node.display_text}
            </div>
          )}
        </Section>
        {node.anchors.length > 0 && (
          <Section title={`锚点 · ${node.anchors.length}`}>
            {node.anchors.map((a, i) => (
              <Row
                key={i}
                name={`@${a.index}`}
                value={`${a.head} ${Object.entries(a.params)
                  .map(([k, v]) => `${k}=${String(v)}`)
                  .join(" ")}`}
              />
            ))}
          </Section>
        )}
        {node.prev.length > 0 && (
          <Section title={`前指令 · ${node.prev.length}`}>
            {node.prev.map((ins, i) => (
              <div key={i} className="px-2 py-0.5 font-mono text-xs text-zinc-300">
                &lt; {spec ? (emitInst(ins, spec) ?? ins.head) : ins.head}
              </div>
            ))}
          </Section>
        )}
        {node.post.length > 0 && (
          <Section title={`后指令 · ${node.post.length}`}>
            {node.post.map((ins, i) => (
              <div key={i} className="px-2 py-0.5 font-mono text-xs text-zinc-300">
                &gt; {spec ? (emitInst(ins, spec) ?? ins.head) : ins.head}
              </div>
            ))}
          </Section>
        )}
      </>
    );
  }

  if (node.kind === "inst") {
    return (
      <>
        <Section title="指令">
          <Row name="head" value={node.head} />
        </Section>
        <Section title="参数">
          <InstView inst={node} />
          <ParamMeta head={node.head} />
        </Section>
      </>
    );
  }

  if (node.kind === "jump") {
    return (
      <Section title="跳转">
        <Row name="target" value={node.target} />
      </Section>
    );
  }

  if (node.kind === "option_group" || node.kind === "cond") {
    const outs = (graph?.edges ?? []).filter(
      (e) => e.from === node.id && (e.kind === "option" || e.kind === "branch"),
    );
    return (
      <Section title={node.kind === "option_group" ? "选项" : "分支"}>
        {outs.map((e, i) => (
          <div key={i} className="px-2 py-1 text-xs">
            <span className="text-zinc-200">{e.text ?? (e.cond ? `if ${e.cond}` : "else")}</span>
            {e.text && e.cond && (
              <span className="ml-2 font-mono text-[10px] text-warn">if:{e.cond}</span>
            )}
            <span className="ml-2 font-mono text-[10px] text-zinc-600">→ {e.to}</span>
          </div>
        ))}
      </Section>
    );
  }

  return (
    <Section title="节点">
      <Row name="kind" value={node.kind} />
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
      {node && <NodeView node={node} />}
    </Panel>
  );
}
