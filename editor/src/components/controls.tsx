// 统一表单控件：bg-base、border-grid、focus 描边 accent、圆角 6px；mono 用于指令名/参数名。

import { useEffect, useRef, type ReactNode } from "react";

const base =
  "rounded-md border border-grid bg-base px-2 py-1 text-xs text-ink outline-none transition-colors placeholder:text-dim focus:border-accent/60 disabled:opacity-40";

export const inputCls = `w-full ${base}`;

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="mb-2 block px-2">
      <div className="mb-1 font-mono text-[10px] tracking-widest text-mut uppercase">{label}</div>
      {children}
    </label>
  );
}

export function TextInput({
  value,
  onChange,
  placeholder,
  mono,
  list,
  disabled,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  mono?: boolean;
  list?: string;
  disabled?: boolean;
}) {
  return (
    <input
      type="text"
      value={value}
      list={list}
      disabled={disabled}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className={`${inputCls} ${mono ? "font-mono" : ""}`}
    />
  );
}

export function TextArea({
  value,
  onChange,
  rows = 4,
  mono,
  placeholder,
}: {
  value: string;
  onChange: (v: string) => void;
  rows?: number;
  mono?: boolean;
  placeholder?: string;
}) {
  return (
    <textarea
      value={value}
      rows={rows}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className={`${inputCls} resize-y leading-relaxed ${mono ? "font-mono" : ""}`}
    />
  );
}

export function NumberInput({
  value,
  onChange,
  step,
  placeholder,
}: {
  value: number | undefined;
  onChange: (v: number | undefined) => void;
  step?: number;
  placeholder?: string;
}) {
  return (
    <input
      type="number"
      value={value ?? ""}
      step={step}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value === "" ? undefined : Number(e.target.value))}
      className={`${inputCls} font-mono`}
    />
  );
}

export function BoolSwitch({
  checked,
  onChange,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`flex h-5 w-9 items-center rounded-full border px-0.5 transition-colors ${
        checked ? "justify-end border-accent/60 bg-accent/25" : "justify-start border-grid bg-base"
      }`}
    >
      <span
        className={`h-3.5 w-3.5 rounded-full transition-colors ${checked ? "bg-accent" : "bg-dim"}`}
      />
    </button>
  );
}

export function SelectInput({
  value,
  options,
  onChange,
  mono,
  className,
}: {
  value: string;
  options: string[];
  onChange: (v: string) => void;
  mono?: boolean;
  className?: string;
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className={`${base} ${mono ? "font-mono" : ""} ${className ?? ""}`}
    >
      {options.map((o) => (
        <option key={o} value={o} className="bg-base">
          {o}
        </option>
      ))}
    </select>
  );
}

export function SmallButton({
  onClick,
  title,
  danger,
  disabled,
  children,
  className,
}: {
  onClick: () => void;
  title?: string;
  danger?: boolean;
  disabled?: boolean;
  children: ReactNode;
  className?: string;
}) {
  return (
    <button
      type="button"
      title={title}
      disabled={disabled}
      onClick={onClick}
      className={`rounded-md border px-1.5 py-0.5 font-mono text-[10px] leading-4 transition-colors disabled:opacity-35 ${
        danger
          ? "border-danger/30 text-danger hover:bg-danger/10"
          : "border-grid text-mut hover:border-accent/40 hover:text-accent"
      } ${className ?? ""}`}
    >
      {children}
    </button>
  );
}

/** 原生 datalist 候选（配合 TextInput 的 list 属性） */
export function Datalist({ id, options }: { id: string; options: string[] }) {
  return (
    <datalist id={id}>
      {options.map((o) => (
        <option key={o} value={o} />
      ))}
    </datalist>
  );
}

/** 自动高度 textarea（行内编辑用）：高度随内容伸缩，autoFocus 时光标落末位 */
export function AutoTextarea({
  value,
  onChange,
  onKeyDown,
  onBlur,
  autoFocus,
  placeholder,
  className,
}: {
  value: string;
  onChange: (v: string) => void;
  onKeyDown?: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  onBlur?: (e: React.FocusEvent<HTMLTextAreaElement>) => void;
  autoFocus?: boolean;
  placeholder?: string;
  className?: string;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [value]);
  useEffect(() => {
    const el = ref.current;
    if (el && autoFocus) {
      el.focus();
      el.setSelectionRange(el.value.length, el.value.length);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 仅挂载时聚焦一次
  }, []);
  return (
    <textarea
      ref={ref}
      rows={1}
      value={value}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      onKeyDown={onKeyDown}
      onBlur={onBlur}
      className={`resize-none overflow-hidden ${className ?? ""}`}
    />
  );
}
