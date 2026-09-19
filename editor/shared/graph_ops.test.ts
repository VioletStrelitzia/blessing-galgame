import { describe, expect, it } from "vitest";
import type { BgalsGraph, DialogueNode } from "./graph";
import {
  addBranch,
  addComment,
  addOption,
  appendAfter,
  appendEnd,
  insertOnEdge,
  makeComment,
  makeCond,
  makeDialogue,
  makeInst,
  makeJump,
  makeOptionGroup,
  moveOption,
  removeBranch,
  removeComment,
  removeNode,
  removeOption,
  setSlot,
  updateBranch,
  updateComment,
  updateDialogue,
  updateInstParams,
  updateJump,
  updateOption,
} from "./graph_ops";

function dlg(id: string, character = "", text = id): DialogueNode {
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

/** start → a → b → end */
function linearGraph(): BgalsGraph {
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [{ id: "start", kind: "start" }, dlg("a", "甲"), dlg("b"), { id: "end", kind: "end" }],
    edges: [
      { from: "start", to: "a", kind: "seq" },
      { from: "a", to: "b", kind: "seq" },
      { from: "b", to: "end", kind: "seq" },
    ],
  };
}

/** start → g；g -甲→ x → m；g -乙→ m（空体）；m → end */
function optionGraph(): BgalsGraph {
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [
      { id: "start", kind: "start" },
      { id: "g", kind: "option_group" },
      dlg("x"),
      dlg("m", "", "汇合"),
      { id: "end", kind: "end" },
    ],
    edges: [
      { from: "start", to: "g", kind: "seq" },
      { from: "g", to: "x", kind: "option", text: "甲" },
      { from: "g", to: "m", kind: "option", text: "乙" },
      { from: "x", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ],
  };
}

/** 嵌套：start → g；g -A→ c(cond)；c -if→ p → m；c -else→ m；g -B→ m；m → end */
function nestedGraph(): BgalsGraph {
  return {
    format: "bgals-graph/1",
    compiler: "test",
    script: "t",
    nodes: [
      { id: "start", kind: "start" },
      { id: "g", kind: "option_group" },
      { id: "c", kind: "cond" },
      dlg("p"),
      dlg("m", "", "汇合"),
      { id: "end", kind: "end" },
    ],
    edges: [
      { from: "start", to: "g", kind: "seq" },
      { from: "g", to: "c", kind: "option", text: "A" },
      { from: "g", to: "m", kind: "option", text: "B" },
      { from: "c", to: "p", kind: "branch", cond: "x >= 1" },
      { from: "c", to: "m", kind: "branch" },
      { from: "p", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ],
  };
}

const seqEdges = (g: BgalsGraph) => g.edges.filter((e) => e.kind === "seq");
const branchEdges = (g: BgalsGraph, from: string) =>
  g.edges.filter((e) => e.from === from && (e.kind === "option" || e.kind === "branch"));

describe("insertOnEdge", () => {
  it("在 seq 边上插入节点：断原边、接两条新 seq 边", () => {
    const g = insertOnEdge(linearGraph(), 1, dlg("n", "", "新"));
    expect(seqEdges(g)).toEqual([
      { from: "start", to: "a", kind: "seq" },
      { from: "a", to: "n", kind: "seq" },
      { from: "n", to: "b", kind: "seq" },
      { from: "b", to: "end", kind: "seq" },
    ]);
    expect(g.nodes.some((n) => n.id === "n")).toBe(true);
  });

  it("不改入参（不可变性）", () => {
    const g0 = linearGraph();
    const snapshot = structuredClone(g0);
    insertOnEdge(g0, 1, dlg("n"));
    expect(g0).toEqual(snapshot);
  });

  it("插入 makeOptionGroup 草稿：默认两个空选项直接指向后继汇合点", () => {
    const g = insertOnEdge(linearGraph(), 1, makeOptionGroup("og"));
    expect(seqEdges(g)).toContainEqual({ from: "a", to: "og", kind: "seq" });
    expect(branchEdges(g, "og")).toEqual([
      { from: "og", to: "b", kind: "option", text: "选项 1" },
      { from: "og", to: "b", kind: "option", text: "选项 2" },
    ]);
  });

  it("插入 makeCond 草稿：默认 if+else 两空分支；裸 cond 节点默认 true+else", () => {
    const g = insertOnEdge(linearGraph(), 1, makeCond("x >= 1", "cd"));
    expect(branchEdges(g, "cd")).toEqual([
      { from: "cd", to: "b", kind: "branch", cond: "x >= 1" },
      { from: "cd", to: "b", kind: "branch" },
    ]);
    const g2 = insertOnEdge(linearGraph(), 1, { id: "cd2", kind: "cond" });
    expect(branchEdges(g2, "cd2")).toEqual([
      { from: "cd2", to: "b", kind: "branch", cond: "true" },
      { from: "cd2", to: "b", kind: "branch" },
    ]);
  });

  it("反例：非 seq 边 / 越界 / jump / comment / 重复 id", () => {
    const og = optionGraph();
    expect(() => insertOnEdge(og, 1, dlg("n"))).toThrow("只能在 seq 顺序边上插入节点");
    expect(() => insertOnEdge(linearGraph(), 99, dlg("n"))).toThrow("边下标越界");
    expect(() => insertOnEdge(linearGraph(), 1, makeJump("s2"))).toThrow("终端节点");
    expect(() => insertOnEdge(linearGraph(), 1, makeComment("hi"))).toThrow("comment");
    expect(() => insertOnEdge(linearGraph(), 1, dlg("a"))).toThrow("id 已存在");
  });
});

describe("appendAfter / appendEnd", () => {
  it("插到某节点之后（其 seq 出边目标之前）", () => {
    const g = appendAfter(linearGraph(), "a", dlg("n"));
    expect(seqEdges(g)).toContainEqual({ from: "a", to: "n", kind: "seq" });
    expect(seqEdges(g)).toContainEqual({ from: "n", to: "b", kind: "seq" });
  });

  it("组节点之后：新节点成为新汇合点，原入边改指新节点", () => {
    const g = appendAfter(optionGraph(), "g", dlg("n", "", "过场"));
    expect(g.edges).toContainEqual({ from: "x", to: "n", kind: "seq" });
    expect(g.edges).toContainEqual({ from: "g", to: "n", kind: "option", text: "乙" });
    expect(g.edges).toContainEqual({ from: "n", to: "m", kind: "seq" });
    expect(g.edges.filter((e) => e.to === "m")).toEqual([{ from: "n", to: "m", kind: "seq" }]);
  });

  it("无 seq 后继的尾节点：直接接尾并续到 end", () => {
    const g0 = linearGraph();
    g0.edges = g0.edges.filter((e) => e.from !== "b"); // b 成为无后继尾节点
    const g = appendAfter(g0, "b", dlg("n"));
    expect(seqEdges(g)).toContainEqual({ from: "b", to: "n", kind: "seq" });
    expect(seqEdges(g)).toContainEqual({ from: "n", to: "end", kind: "seq" });
  });

  it("appendEnd：图只有 start/end 时插中间；否则插到主链进入 end 之前", () => {
    const empty: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "end", kind: "end" },
      ],
      edges: [{ from: "start", to: "end", kind: "seq" }],
    };
    const g = appendEnd(empty, dlg("n"));
    expect(seqEdges(g)).toEqual([
      { from: "start", to: "n", kind: "seq" },
      { from: "n", to: "end", kind: "seq" },
    ]);
    const g2 = appendEnd(linearGraph(), dlg("n2"));
    expect(seqEdges(g2)).toContainEqual({ from: "b", to: "n2", kind: "seq" });
    expect(seqEdges(g2)).toContainEqual({ from: "n2", to: "end", kind: "seq" });
  });

  it("反例：jump/end 之后追加、组无汇合点、主链不到 end", () => {
    expect(() => appendAfter(linearGraph(), "end", dlg("n"))).toThrow("end 之后不能追加");
    const withJump = appendEnd(linearGraph(), makeJump("main_menu", "j"));
    expect(() => appendAfter(withJump, "j", dlg("n"))).toThrow("终端节点");
    expect(() => appendEnd(withJump, dlg("n"))).toThrow("主流程未到达 end");
    const noMerge: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "g", kind: "option_group" },
        { id: "j1", kind: "jump", target: "s1" },
        { id: "j2", kind: "jump", target: "s2" },
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "g", kind: "seq" },
        { from: "g", to: "j1", kind: "option", text: "一" },
        { from: "g", to: "j2", kind: "option", text: "二" },
      ],
    };
    expect(() => appendAfter(noMerge, "g", dlg("n"))).toThrow("没有汇合点");
  });
});

describe("removeNode", () => {
  it("普通节点：前驱 → 后继 seq 重连", () => {
    const g = removeNode(linearGraph(), "a");
    expect(seqEdges(g)).toEqual([
      { from: "start", to: "b", kind: "seq" },
      { from: "b", to: "end", kind: "seq" },
    ]);
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "b", "end"]);
  });

  it("选项组：独占子图收敛，前驱与汇合后继重连", () => {
    const g = removeNode(optionGraph(), "g");
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "m", "end"]);
    expect(g.edges).toEqual([
      { from: "start", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ]);
  });

  it("嵌套：删除选项体内的条件节点，分支体收敛为空体", () => {
    const g = removeNode(nestedGraph(), "c");
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "g", "m", "end"]);
    expect(branchEdges(g, "g")).toEqual([
      { from: "g", to: "m", kind: "option", text: "A" },
      { from: "g", to: "m", kind: "option", text: "B" },
    ]);
  });

  it("嵌套：删除含条件子图的整个选项组", () => {
    const g = removeNode(nestedGraph(), "g");
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "m", "end"]);
    expect(g.edges).toEqual([
      { from: "start", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ]);
  });

  it("被组外其他路径可达的共享节点不连带删除", () => {
    // start → c(cond)；c -if→ g；c -else→ s；g -A→ s；g -B→ m；s → m；m → end
    const g0: BgalsGraph = {
      format: "bgals-graph/1",
      compiler: "test",
      script: "t",
      nodes: [
        { id: "start", kind: "start" },
        { id: "c", kind: "cond" },
        { id: "g", kind: "option_group" },
        dlg("s"),
        dlg("m"),
        { id: "end", kind: "end" },
      ],
      edges: [
        { from: "start", to: "c", kind: "seq" },
        { from: "c", to: "g", kind: "branch", cond: "x >= 1" },
        { from: "c", to: "s", kind: "branch" },
        { from: "g", to: "s", kind: "option", text: "A" },
        { from: "g", to: "m", kind: "option", text: "B" },
        { from: "s", to: "m", kind: "seq" },
        { from: "m", to: "end", kind: "seq" },
      ],
    };
    const g = removeNode(g0, "g");
    expect(g.nodes.map((n) => n.id)).toContain("s");
    expect(g.edges).toContainEqual({ from: "c", to: "m", kind: "branch", cond: "x >= 1" });
    expect(g.edges).toContainEqual({ from: "c", to: "s", kind: "branch" });
  });

  it("删除分支体首节点：option 入边改指其后继（分支变空体）", () => {
    const g = removeNode(optionGraph(), "x");
    expect(branchEdges(g, "g")).toEqual([
      { from: "g", to: "m", kind: "option", text: "甲" },
      { from: "g", to: "m", kind: "option", text: "乙" },
    ]);
  });

  it("终端 jump 节点：seq 入边删除", () => {
    const g0 = appendEnd(linearGraph(), makeJump("main_menu", "j"));
    const g = removeNode(g0, "j");
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "a", "b", "end"]);
    expect(g.edges.filter((e) => e.to === "j" || e.from === "j")).toEqual([]);
  });

  it("附着在被删节点上的注释降级为文件头", () => {
    const g0 = addComment(linearGraph(), "a", "备忘", "cm");
    const g = removeNode(g0, "a");
    const c = g.nodes.find((n) => n.id === "cm");
    expect(c).toMatchObject({ kind: "comment", before: null });
  });

  it("反例：start/end 不可删；节点不存在", () => {
    expect(() => removeNode(linearGraph(), "start")).toThrow("start/end 节点不可删除");
    expect(() => removeNode(linearGraph(), "end")).toThrow("start/end 节点不可删除");
    expect(() => removeNode(linearGraph(), "nope")).toThrow("节点不存在");
  });
});

describe("updateDialogue / updateInstParams / setSlot", () => {
  it("updateJump：替换跳转目标；空目标与类型不符报错", () => {
    const g0 = linearGraph();
    const g1 = appendEnd(g0, makeJump("demo_scene2", "j"));
    const g = updateJump(g1, "j", "main_menu");
    expect(g.nodes.find((n) => n.id === "j")).toMatchObject({ kind: "jump", target: "main_menu" });
    expect(() => updateJump(g1, "j", "  ")).toThrow("不能为空");
    expect(() => updateJump(g1, "a", "x")).toThrow("不是 jump");
  });

  it("updateDialogue：局部补丁；改 text 时派生字段失效", () => {
    const g0 = linearGraph();
    const g = updateDialogue(g0, "a", { character: "乙" });
    expect(g.nodes.find((n) => n.id === "a")).toMatchObject({ character: "乙", text: "a" });
    const g2 = updateDialogue(g0, "a", { text: "新台词" });
    expect(g2.nodes.find((n) => n.id === "a")).toMatchObject({
      text: "新台词",
      display_text: "新台词",
      anchors: [],
    });
    expect(() => updateDialogue(optionGraph(), "g", {})).toThrow("不是 dialogue");
  });

  it("updateInstParams：整体替换 params", () => {
    const g0 = linearGraph();
    const g1 = insertOnEdge(g0, 1, makeInst("MUSIC_PLAY", "mi"));
    const g = updateInstParams(g1, "mi", { path: "bgm", volume: 0.5 });
    expect(g.nodes.find((n) => n.id === "mi")).toMatchObject({
      params: { path: "bgm", volume: 0.5 },
    });
    const g2 = updateInstParams(g, "mi", {});
    expect(g2.nodes.find((n) => n.id === "mi")).toMatchObject({ params: {} });
    expect(() => updateInstParams(g0, "a", {})).toThrow("不是 inst");
  });

  it("setSlot：编辑对话前/后指令槽", () => {
    const g = setSlot(linearGraph(), "a", "prev", [{ head: "WAIT", params: { duration: 0.5 } }]);
    expect(g.nodes.find((n) => n.id === "a")).toMatchObject({
      prev: [{ kind: "inst", head: "WAIT", params: { duration: 0.5 } }],
    });
    const g2 = setSlot(g, "a", "post", [{ head: "SFX_STOP", params: {} }]);
    expect(g2.nodes.find((n) => n.id === "a")).toMatchObject({
      post: [{ kind: "inst", head: "SFX_STOP", params: {} }],
    });
    expect(() => setSlot(optionGraph(), "g", "prev", [])).toThrow("不是 dialogue");
  });
});

describe("选项组操作", () => {
  it("addOption：空体新分支指向组的汇合点，追加在末位选项之后", () => {
    const g = addOption(optionGraph(), "g", { text: "丙", cond: "x > 0" });
    expect(branchEdges(g, "g")).toEqual([
      { from: "g", to: "x", kind: "option", text: "甲" },
      { from: "g", to: "m", kind: "option", text: "乙" },
      { from: "g", to: "m", kind: "option", text: "丙", cond: "x > 0" },
    ]);
    expect(() => addOption(nestedGraph(), "c", { text: "x" })).toThrow("不是选项组");
  });

  it("updateOption：改文本/条件；cond 传 null 清除", () => {
    const g0 = addOption(optionGraph(), "g", { text: "丙", cond: "x > 0" });
    const idx = g0.edges.findIndex((e) => e.text === "丙");
    const g = updateOption(g0, "g", idx, { text: "丙改", cond: null });
    expect(g.edges[idx]).toEqual({ from: "g", to: "m", kind: "option", text: "丙改" });
    expect(() => updateOption(g0, "g", 0, { text: "x" })).toThrow("不是节点 g 的 option 出边");
  });

  it("removeOption：删分支并收敛独占子图", () => {
    const g = removeOption(optionGraph(), "g", 1);
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "g", "m", "end"]);
    expect(branchEdges(g, "g")).toEqual([{ from: "g", to: "m", kind: "option", text: "乙" }]);
  });

  it("removeOption：剩 0 条时连组删掉并重连（单分支体相当于内联展开）", () => {
    // 先删到只剩 -甲→ x → m，再删最后一条：组消失，start → x → m
    const g1 = removeOption(optionGraph(), "g", 2);
    const g = removeOption(g1, "g", 1);
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "x", "m", "end"]);
    expect(seqEdges(g)).toEqual([
      { from: "start", to: "x", kind: "seq" },
      { from: "x", to: "m", kind: "seq" },
      { from: "m", to: "end", kind: "seq" },
    ]);
  });

  it("moveOption：交换分支序；边界抛错", () => {
    const g = moveOption(optionGraph(), "g", 2, -1);
    expect(branchEdges(g, "g")).toEqual([
      { from: "g", to: "m", kind: "option", text: "乙" },
      { from: "g", to: "x", kind: "option", text: "甲" },
    ]);
    expect(() => moveOption(optionGraph(), "g", 1, -1)).toThrow("边界");
    expect(() => moveOption(optionGraph(), "g", 2, 1)).toThrow("边界");
  });
});

describe("条件链操作", () => {
  it("addBranch：在 else 之前插入新 elif 空体分支", () => {
    const g = addBranch(nestedGraph(), "c", "x >= 2");
    expect(branchEdges(g, "c")).toEqual([
      { from: "c", to: "p", kind: "branch", cond: "x >= 1" },
      { from: "c", to: "m", kind: "branch", cond: "x >= 2" },
      { from: "c", to: "m", kind: "branch" },
    ]);
    expect(() => addBranch(nestedGraph(), "c", "  ")).toThrow("条件不能为空");
    expect(() => addBranch(optionGraph(), "g", "x")).toThrow("不是条件链");
  });

  it("updateBranch：else 边禁改 cond", () => {
    const g = updateBranch(nestedGraph(), "c", 3, "x < 0");
    expect(g.edges[3]).toMatchObject({ cond: "x < 0" });
    expect(() => updateBranch(nestedGraph(), "c", 4, "x")).toThrow("else 分支不可设置条件");
  });

  it("removeBranch：删分支收敛子图；else 可删；至少保留一条分支", () => {
    const g = removeBranch(nestedGraph(), "c", 3);
    expect(g.nodes.map((n) => n.id)).toEqual(["start", "g", "c", "m", "end"]);
    expect(branchEdges(g, "c")).toEqual([{ from: "c", to: "m", kind: "branch" }]);
    // 单分支（else）再删 → 抛错
    const lastIdx = g.edges.findIndex((e) => e.from === "c" && e.kind === "branch");
    expect(() => removeBranch(g, "c", lastIdx)).toThrow("至少保留一条分支");
  });
});

describe("注释操作与工厂", () => {
  it("addComment / updateComment / removeComment", () => {
    let g = addComment(linearGraph(), null, "文件头注", "c1");
    g = addComment(g, "a", "附着 a", "c2");
    expect(g.nodes.find((n) => n.id === "c1")).toMatchObject({ kind: "comment", before: null });
    expect(g.nodes.find((n) => n.id === "c2")).toMatchObject({ before: "a", text: "附着 a" });
    expect(g.edges.filter((e) => e.from === "c1" || e.to === "c1")).toEqual([]);
    g = updateComment(g, "c2", "改注");
    expect(g.nodes.find((n) => n.id === "c2")).toMatchObject({ text: "改注" });
    g = removeComment(g, "c2");
    expect(g.nodes.some((n) => n.id === "c2")).toBe(false);
    expect(() => addComment(linearGraph(), "nope", "x")).toThrow("节点不存在");
    expect(() => updateComment(linearGraph(), "a", "x")).toThrow("不是 comment");
    expect(() => removeComment(linearGraph(), "a")).toThrow("不是 comment");
  });

  it("removeNode 也可删 comment", () => {
    const g = removeNode(addComment(linearGraph(), "a", "注", "c1"), "c1");
    expect(g.nodes.some((n) => n.id === "c1")).toBe(false);
  });

  it("工厂：默认形态与 id 生成", () => {
    expect(makeDialogue("d1")).toMatchObject({ kind: "dialogue", prev: [], post: [] });
    expect(makeInst("WAIT", "i1")).toEqual({ id: "i1", kind: "inst", head: "WAIT", params: {} });
    expect(makeJump("s2", "j1")).toEqual({ id: "j1", kind: "jump", target: "s2" });
    expect(makeComment("注", "c1")).toEqual({
      id: "c1",
      kind: "comment",
      text: "注",
      before: null,
    });
    expect(makeOptionGroup("og")).toEqual({
      node: { id: "og", kind: "option_group" },
      branches: [{ text: "选项 1" }, { text: "选项 2" }],
    });
    expect(makeCond("x", "cd")).toEqual({
      node: { id: "cd", kind: "cond" },
      branches: [{ cond: "x" }, {}],
    });
    expect(makeDialogue().id).not.toBe(makeDialogue().id);
    expect(makeDialogue().id).toHaveLength(8);
  });
});
