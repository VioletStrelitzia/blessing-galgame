import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { emitGraph, emitInst, escapeDialogueLine } from "./emit";
import type { BgalsGraph, DialogueNode } from "./graph";
import type { BgalsSpec } from "./spec";

function loadFixture<T>(rel: string): T {
  const url = new URL(`../public/fixtures/${rel}`, import.meta.url);
  return JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as T;
}

const spec = loadFixture<BgalsSpec>("spec.json");
const demo1 = loadFixture<BgalsGraph>("graphs/demo_scene1.json");
const demo3 = loadFixture<BgalsGraph>("graphs/demo_scene3.json");

function dialogue(id: string, character: string, text: string): DialogueNode {
  return {
    id,
    kind: "dialogue",
    character,
    text,
    display_text: text,
    anchors: [],
    prev: [],
    post: [],
  };
}

describe("escapeDialogueLine", () => {
  it("行首保留字符补 \\", () => {
    expect(escapeDialogueLine("* 像选项的旁白", spec)).toBe("\\* 像选项的旁白");
    expect(escapeDialogueLine("> 像后指令", spec)).toBe("\\> 像后指令");
    expect(escapeDialogueLine("< 像前指令", spec)).toBe("\\< 像前指令");
    expect(escapeDialogueLine("# 像注释", spec)).toBe("\\# 像注释");
    expect(escapeDialogueLine("// 像注释", spec)).toBe("\\// 像注释");
  });

  it("首词命中保留字补 \\", () => {
    expect(escapeDialogueLine("wait 一下再说话", spec)).toBe("\\wait 一下再说话");
    expect(escapeDialogueLine("if 开头的旁白", spec)).toBe("\\if 开头的旁白");
  });

  it("普通对话行不动", () => {
    expect(escapeDialogueLine("引路人: 你好。", spec)).toBe("引路人: 你好。");
    expect(escapeDialogueLine("这是旁白。", spec)).toBe("这是旁白。");
  });
});

describe("emitInst", () => {
  it("仅写非默认值", () => {
    expect(emitInst({ kind: "inst", head: "MUSIC_PLAY", params: { path: "demo_bgm" } }, spec)).toBe(
      "music demo_bgm",
    );
  });

  it("非默认值按 spec 参数序发射", () => {
    expect(
      emitInst(
        { kind: "inst", head: "MUSIC_PLAY", params: { path: "bgm", volume: 0.5, loop: false } },
        spec,
      ),
    ).toBe("music bgm loop:false volume:0.5");
  });

  it("位置参数缺省回退 spec 默认值（char_index）", () => {
    expect(
      emitInst({ kind: "inst", head: "CHAR_SETUP", params: { path: "p", x: 0.3, y: 0.95 } }, spec),
    ).toBe("char 0 setup p 0.3,0.95");
  });

  it("duration → time 键名映射；布尔值小写", () => {
    expect(
      emitInst(
        { kind: "inst", head: "CHAR_SHOW_FADE", params: { duration: 0.6, wait: true } },
        spec,
      ),
    ).toBe("char 0 show time:0.6 wait:true");
  });

  it("sfx stop 省略空引用", () => {
    expect(emitInst({ kind: "inst", head: "SFX_STOP", params: { fade: 0.5 } }, spec)).toBe(
      "sfx stop fade:0.5",
    );
  });

  it("结构指令不发射；未知指令头降级为注释行", () => {
    expect(emitInst({ kind: "inst", head: "OPTION", params: {} }, spec)).toBeNull();
    expect(emitInst({ kind: "inst", head: "NOPE", params: {} }, spec)).toBe("# 未识别指令头: NOPE");
  });
});

describe("emitGraph", () => {
  it("prev/post 以 </> 前缀行附着对话前后，lineMap 覆盖全部产出行", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        {
          ...dialogue("n0", "甲", "台词"),
          prev: [{ kind: "inst", head: "WAIT", params: { duration: 0.5 } }],
          post: [{ kind: "inst", head: "SFX_STOP", params: { fade: 0.5 } }],
        },
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "n0", kind: "seq" },
        { from: "n0", to: "end", kind: "seq" },
      ],
    };
    const { text, lineMap } = emitGraph(graph, spec);
    expect(text).toBe("< wait 0.5\n甲: 台词\n> sfx stop fade:0.5\n");
    expect(lineMap["n0"]).toEqual({ from: 1, to: 3 });
    expect(lineMap["start"]).toBeUndefined();
  });

  it("选项体内套条件分支的缩进嵌套；空选项体直接汇合", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "n0", kind: "option_group" },
        { id: "n1", kind: "cond" },
        dialogue("n2", "甲", "你好"),
        dialogue("n3", "", "旁白"),
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "n0", kind: "seq" },
        { from: "n0", to: "n1", kind: "option", text: "去" },
        { from: "n0", to: "end", kind: "option", text: "不去" },
        { from: "n1", to: "n2", kind: "branch", cond: "x >= 1" },
        { from: "n1", to: "n3", kind: "branch" },
        { from: "n2", to: "end", kind: "seq" },
        { from: "n3", to: "end", kind: "seq" },
      ],
    };
    expect(emitGraph(graph, spec).text).toBe(
      "* 去\n    if x >= 1\n        甲: 你好\n    else\n        旁白\n* 不去\n",
    );
  });

  it("elif/else 链", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "n0", kind: "cond" },
        dialogue("n1", "", "一"),
        dialogue("n2", "", "二"),
        dialogue("n3", "", "三"),
        dialogue("n4", "", "汇合"),
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "n0", kind: "seq" },
        { from: "n0", to: "n1", kind: "branch", cond: "x >= 1" },
        { from: "n0", to: "n2", kind: "branch", cond: "x >= 0" },
        { from: "n0", to: "n3", kind: "branch" },
        { from: "n1", to: "n4", kind: "seq" },
        { from: "n2", to: "n4", kind: "seq" },
        { from: "n3", to: "n4", kind: "seq" },
        { from: "n4", to: "end", kind: "seq" },
      ],
    };
    expect(emitGraph(graph, spec).text).toBe(
      "if x >= 1\n    一\nelif x >= 0\n    二\nelse\n    三\n汇合\n",
    );
  });

  it("demo_scene1 fixture 发射含关键行", () => {
    const out = emitGraph(demo1, spec).text;
    expect(out).toContain("bg demo_stage\n");
    expect(out).toContain("music demo_bgm\n");
    expect(out).toContain("char 0 setup demo_char_a 0.3,0.95\n");
    expect(out).toContain("引路人: 欢迎来到 Blessing Galgame Engine 的最小演示。");
    expect(out).toContain("> bg demo_stage_night time:1\n");
    expect(out).toContain("< char 0 move 0.5,0.95\n");
    expect(out).toContain("引路人: 立绘可以移动[char 0 texture demo_char_b]、换图、淡入淡出。");
    expect(out).toContain("var affection = 1\n");
    expect(out).toContain("* 前往第二幕\n");
    expect(out).toContain("* 留在这里 if:affection >= 1\n");
    expect(out).toContain("if affection >= 1 and affection < 100\n");
    expect(out).toContain("else\n");
    expect(out).toContain("jump demo_scene2\n");
    expect(out).toContain("begin demo_scene1\n");
    expect(out).toContain("jump main_menu\n");
  });

  it("demo_scene3 fixture：scene/trans/音频子动作", () => {
    const out = emitGraph(demo3, spec).text;
    expect(out).toContain("scene mount ui 演出层 res://Scenes/OptionUI/option_ui.tscn time:0.5\n");
    expect(out).toContain("trans out time:0.5\n");
    expect(out).toContain("trans in time:0.5\n");
    expect(out).toContain("wait 1\n");
    expect(out).toContain("sfx demo_bgm volume:0.15 loop:true\n");
    expect(out).toContain("music volume 0.4 fade:0.8\n");
    expect(out).toContain("sfx stop demo_bgm fade:0.5\n");
    expect(out).toContain("music volume 1 fade:0.8\n");
    expect(out).toContain("music demo_bgm_2 fade_in:2 fade_out:0.3\n");
    expect(out).toContain("sfx volume demo_bgm 0.4 fade:1.5\n");
    expect(out).toContain("char 0 move 0.7,0.95 time:0.5 wait:true\n");
  });

  it("comment：before=null 放文件头，否则在目标节点首行之前（同缩进）", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "c0", kind: "comment", text: "文件头注", before: null },
        { id: "g", kind: "option_group" },
        dialogue("n1", "", "体内"),
        { id: "c1", kind: "comment", text: "组前注", before: "g" },
        { id: "c2", kind: "comment", text: "体内注", before: "n1" },
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "g", kind: "seq" },
        { from: "g", to: "n1", kind: "option", text: "去" },
        { from: "g", to: "end", kind: "option", text: "不去" },
        { from: "n1", to: "end", kind: "seq" },
      ],
    };
    const { text, lineMap } = emitGraph(graph, spec);
    expect(text).toBe("# 文件头注\n# 组前注\n* 去\n    # 体内注\n    体内\n* 不去\n");
    expect(lineMap["c0"]).toEqual({ from: 1, to: 1 });
    expect(lineMap["c1"]).toEqual({ from: 2, to: 2 });
    expect(lineMap["c2"]).toEqual({ from: 4, to: 4 });
    expect(lineMap["g"]).toEqual({ from: 3, to: 6 });
    expect(lineMap["n1"]).toEqual({ from: 5, to: 5 });
  });

  it("comment：附着目标缺失或不可达时降级到文件头/文件尾，不丢数据", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        dialogue("n0", "", "正文"),
        { id: "c0", kind: "comment", text: "目标已不存在", before: "ghost" },
        { id: "c1", kind: "comment", text: "目标不可达", before: "lost" },
        dialogue("lost", "", "孤悬"),
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "n0", kind: "seq" },
        { from: "n0", to: "end", kind: "seq" },
      ],
    };
    const { text, lineMap } = emitGraph(graph, spec);
    expect(text).toBe("# 目标已不存在\n正文\n# 目标不可达\n");
    expect(lineMap["lost"]).toBeUndefined();
  });

  it("lineMap：fixture 关键节点的行号与文本吻合", () => {
    const { text, lineMap } = emitGraph(demo1, spec);
    const lines = text.split("\n");
    const span = (id: string) => lines.slice(lineMap[id].from - 1, lineMap[id].to).join("\n");
    expect(span("n0")).toBe("bg demo_stage");
    expect(span("n22").trim()).toBe("jump main_menu");
    expect(span("n12")).toContain("* 前往第二幕");
    expect(span("n12")).toContain("* 留在这里 if:affection >= 1");
    expect(span("n17")).toContain("if affection >= 1 and affection < 100");
  });

  it("空分支体不产生多余缩进块；start/end 按 kind 定位而非字面 id", () => {
    const graph: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "s0", kind: "start" },
        { id: "g", kind: "option_group" },
        dialogue("n1", "", "尾部"),
        { id: "e0", kind: "end" },
      ],
      edges: [
        { from: "s0", to: "g", kind: "seq" },
        { from: "g", to: "n1", kind: "option", text: "甲" },
        { from: "g", to: "n1", kind: "option", text: "乙" },
        { from: "n1", to: "e0", kind: "seq" },
      ],
    };
    expect(emitGraph(graph, spec).text).toBe("* 甲\n* 乙\n尾部\n");
  });
});
