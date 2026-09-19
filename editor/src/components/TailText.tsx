// 尾部保留截断：差异在尾部的值（路径/参数/长串）不用 CSS ellipsis 砍尾。
// 路径类值（含 / \ _ 分段）保留最后两段、前缀 …；普通超长字符串保留尾部 max 字符、前缀 …。

/** 纯函数：返回尾部保留的显示文本（全文经组件 title 悬浮可查） */
export function tailText(s: string, max = 24): string {
  if (s.length <= max) return s;
  const seps: number[] = [];
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "/" || s[i] === "\\") seps.push(i);
  }
  // 无路径分隔符时回退到下划线分段（snake_case 资源键等）
  if (seps.length < 2) {
    seps.length = 0;
    for (let i = 0; i < s.length; i++) {
      if (s[i] === "_") seps.push(i);
    }
  }
  if (seps.length >= 2) {
    const cut = seps[seps.length - 2];
    return "…" + s.slice(cut);
  }
  return "…" + s.slice(-max);
}

export function TailText({
  text,
  max = 24,
  className,
}: {
  text: string;
  max?: number;
  className?: string;
}) {
  return (
    <span className={`whitespace-nowrap ${className ?? ""}`} title={text}>
      {tailText(text, max)}
    </span>
  );
}
