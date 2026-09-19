// spec 驱动的指令参数表单：inst 节点与对话 prev/post 槽共用。
// STR→text、FLOAT/INT→number、BOOL→开关；role=audio/texture→refs datalist，
// role=script→剧本列表 datalist；scene_type→select(world2d/ui)；res_path→text。

import { useId } from "react";
import type { ParamValue, Params } from "../../shared/graph";
import type { SpecParam } from "../../shared/spec";
import { useEditor } from "../state/store";
import { BoolSwitch, Datalist, NumberInput, SelectInput, TextInput } from "../components/controls";

function ParamField({
  p,
  value,
  set,
  listId,
  options,
}: {
  p: SpecParam;
  value: ParamValue | undefined;
  set: (name: string, v: ParamValue | undefined) => void;
  listId: string;
  options: string[];
}) {
  const dflt = typeof p.default === "object" ? undefined : String(p.default);
  let control: React.ReactNode;
  if (p.role === "scene_type") {
    control = (
      <SelectInput
        mono
        value={String(value ?? p.default ?? "world2d")}
        options={["world2d", "ui"]}
        onChange={(v) => set(p.name, v)}
      />
    );
  } else if (p.type === "BOOL") {
    control = (
      <BoolSwitch
        checked={value === undefined ? p.default === true : value === true}
        onChange={(v) => set(p.name, v)}
      />
    );
  } else if (p.type === "INT" || p.type === "FLOAT") {
    control = (
      <NumberInput
        value={typeof value === "number" ? value : undefined}
        step={p.type === "FLOAT" ? 0.1 : 1}
        placeholder={dflt}
        onChange={(v) => set(p.name, v)}
      />
    );
  } else {
    const hasList =
      (p.role === "audio" || p.role === "texture" || p.role === "script") && options.length > 0;
    control = (
      <>
        <TextInput
          mono
          value={typeof value === "string" ? value : value === undefined ? "" : String(value)}
          placeholder={dflt}
          list={hasList ? listId : undefined}
          onChange={(v) => set(p.name, v === "" ? undefined : v)}
        />
        {hasList && <Datalist id={listId} options={options} />}
      </>
    );
  }
  return (
    <>
      <span
        className="self-center overflow-hidden font-mono text-[10px] whitespace-nowrap text-mut"
        title={`${p.type}${p.role ? ` · ${p.role}` : ""}`}
      >
        {p.name}
      </span>
      <span className="min-w-0">{control}</span>
    </>
  );
}

export function InstParamsForm({
  head,
  params,
  onChange,
}: {
  head: string;
  params: Params;
  onChange: (next: Params) => void;
}) {
  const spec = useEditor((s) => s.spec);
  const refs = useEditor((s) => s.refs);
  const scripts = useEditor((s) => s.scripts);
  const uid = useId();
  if (!spec) return null;
  const defs = (spec.spec[head] ?? []).filter((p) => !p.structural);
  if (defs.length === 0) {
    return <div className="px-2 py-1 text-xs text-dim">无参数</div>;
  }
  const set = (name: string, v: ParamValue | undefined) => {
    const next = { ...params };
    if (v === undefined) delete next[name];
    else next[name] = v;
    onChange(next);
  };
  const optionsFor = (p: SpecParam): string[] => {
    if (p.role === "script") return scripts;
    const domain = refs?.[p.role];
    return domain ? Object.keys(domain) : [];
  };
  return (
    <div className="grid grid-cols-[84px_minmax(0,1fr)] items-center gap-x-2 gap-y-1.5 px-2">
      {defs.map((p) => (
        <ParamField
          key={p.name}
          p={p}
          value={params[p.name]}
          set={set}
          listId={`${uid}-${p.name}`}
          options={optionsFor(p)}
        />
      ))}
    </div>
  );
}
