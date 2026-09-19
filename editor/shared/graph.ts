// bgals-graph/1：tool/bgals_cli.gd dump 子命令的图 JSON 契约（GraphDumper.build 输出）。
// 结构回填字段（跳转表）已在 dump 侧消解为图结构，节点 params 只含语义参数且默认值省略。

export type ParamValue = string | number | boolean;
export type Params = Record<string, ParamValue>;

/** 指令载荷：独立指令节点、对话 prev/post 槽、锚点共用此形态 */
export interface InstPayload {
  kind: "inst";
  head: string;
  params: Params;
}

export interface Anchor {
  index: number;
  head: string;
  params: Params;
}

export interface StartNode {
  id: string;
  kind: "start";
}

export interface EndNode {
  id: string;
  kind: "end";
}

export interface InstNode extends InstPayload {
  id: string;
  /** 文件尾/文件首等无处附着的前|后指令，降级为独立指令 */
  dangling?: boolean;
}

export interface DialogueNode {
  id: string;
  kind: "dialogue";
  character: string;
  /** BGalS 原文（锚点、插值原样保留） */
  text: string;
  /** 剥离锚点后的显示文本（插值保持字面） */
  display_text: string;
  anchors: Anchor[];
  prev: InstPayload[];
  post: InstPayload[];
}

export interface OptionGroupNode {
  id: string;
  kind: "option_group";
}

export interface CondNode {
  id: string;
  kind: "cond";
}

export interface JumpNode {
  id: string;
  kind: "jump";
  /** 剧本名或 main_menu */
  target: string;
}

export type GraphNode =
  StartNode | EndNode | InstNode | DialogueNode | OptionGroupNode | CondNode | JumpNode;

export type NodeKind = GraphNode["kind"];

export type EdgeKind = "seq" | "option" | "branch" | "jump";

export interface GraphEdge {
  from: string;
  to: string;
  kind: EdgeKind;
  /** option 边的选项文本 */
  text?: string;
  /** option/branch 边的条件（中缀原文；else 与无条件选项省略） */
  cond?: string;
}

export interface BgalsGraph {
  format: "bgals-graph/1";
  compiler: string;
  script: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
}
