// check 子命令报告契约（tool/bgals_cli.gd check --out report.json）。

export interface Diag {
  file: string;
  line: number;
  level: string;
  msg: string;
}

export interface CheckFile {
  file: string;
  status: string;
}

export interface CheckReport {
  ok: boolean;
  files: CheckFile[];
  diags: Diag[];
}

/** res://scripts/demo/scene1.txt → demo_scene1（镜像 DialogueImporter.script_name_of，read_dir 按默认 scripts/） */
export function scriptNameOfFile(file: string): string {
  return file
    .replace(/^res:\/\//, "")
    .replace(/^scripts\//, "")
    .replace(/\.[^./\\]+$/, "")
    .replace(/[\\/]/g, "_");
}
