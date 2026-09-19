// spec.json：tool/bgals_cli.gd spec 子命令输出，前端指令表单/发射器全部由它驱动（零硬编码指令集）。

import type { ParamValue } from "./graph";

export type ParamType = "STR" | "FLOAT" | "INT" | "BOOL" | "ARR";

export interface SpecParam {
  name: string;
  type: ParamType;
  default: ParamValue | unknown[];
  /** 语义角色（audio/texture/script/res_path/scene_type 或 ""），仅元数据 */
  role: string;
  /** 结构回填字段：dump 已消解，表单与发射器均忽略 */
  structural: boolean;
}

export interface BgalsSpec {
  compiler: string;
  heads: string[];
  spec: Record<string, SpecParam[]>;
  cond_tags: string[];
  anchor_whitelist: string[];
  reserved_keys: string[];
  indent_unit: number;
}
