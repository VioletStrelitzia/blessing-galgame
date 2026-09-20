// bgals-overview/1：tool/bgals_cli.gd overview 子命令的剧本宏观关系契约。
// jump main_menu 的 to = "main_menu"（特殊终态，不在 scripts 里）；
// missing = jump 了但不存在的目标名（渲染为幽灵节点）。

export interface OverviewScript {
  name: string;
  dialogues: number;
  insts: number;
  options: number;
  conds: number;
  jumps: number;
}

export interface OverviewEdge {
  from: string;
  to: string;
  kind: "jump";
}

export interface BgalsOverview {
  format: "bgals-overview/1";
  compiler: string;
  /** begin 指令指定的入口剧本名 */
  begin: string;
  scripts: OverviewScript[];
  edges: OverviewEdge[];
  missing: string[];
}

/** 主菜单终态节点名（特殊，不在 scripts 列表里） */
export const MAIN_MENU = "main_menu";
