import { describe, expect, it } from "vitest";
import type { GraphEdge, GraphNode } from "../../shared/graph";
import { nodeLabel } from "./bridge";

function dlg(text: string): GraphNode {
  return {
    id: "d",
    kind: "dialogue",
    character: "甲",
    text,
    display_text: text,
    anchors: [],
    prev: [],
    post: [],
  };
}

describe("nodeLabel（调试桥 state 命令的节点标签）", () => {
  it("dialogue 取文本前 20 字", () => {
    expect(nodeLabel(dlg("短句"), [])).toBe("短句");
    expect(nodeLabel(dlg("一二三四五六七八九十一二三四五六七八九十一二三四五"), [])).toBe(
      "一二三四五六七八九十一二三四五六七八九十",
    );
  });

  it("inst 取 head，jump 取 target", () => {
    expect(nodeLabel({ id: "i", kind: "inst", head: "MUSIC_PLAY", params: {} }, [])).toBe(
      "MUSIC_PLAY",
    );
    expect(nodeLabel({ id: "j", kind: "jump", target: "demo_scene2" }, [])).toBe("demo_scene2");
  });

  it("option_group 取首选项文本；无出边时退化为 kind", () => {
    const g: GraphNode = { id: "g", kind: "option_group" };
    const edges: GraphEdge[] = [
      { from: "g", to: "a", kind: "option", text: "留下" },
      { from: "g", to: "b", kind: "option", text: "离开" },
    ];
    expect(nodeLabel(g, edges)).toBe("留下");
    expect(nodeLabel(g, [])).toBe("option_group");
  });

  it("其余 kind 标签即 kind", () => {
    expect(nodeLabel({ id: "c", kind: "cond" }, [])).toBe("cond");
    expect(nodeLabel({ id: "m", kind: "comment", text: "便签", before: null }, [])).toBe("comment");
    expect(nodeLabel({ id: "start", kind: "start" }, [])).toBe("start");
  });
});
