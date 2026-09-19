// kind → 语义色（Archify 口径：颜色只表语义）。节点描边/标签/MiniMap 共用。

export const KIND_COLORS: Record<string, string> = {
  start: "#34D399",
  end: "#94A3B8",
  dialogue: "#22D3EE",
  inst: "#A78BFA",
  option_group: "#FBBF24",
  cond: "#FBBF24",
  jump: "#FB7185",
  comment: "#94A3B8",
};

export const FALLBACK_COLOR = "#94A3B8";

export function kindColor(kind: string): string {
  return KIND_COLORS[kind] ?? FALLBACK_COLOR;
}
