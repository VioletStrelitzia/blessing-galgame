import { describe, expect, it } from "vitest";
import { tailText } from "./TailText";

describe("tailText（尾部保留截断）", () => {
  it("短串原样返回", () => {
    expect(tailText("demo_scene1")).toBe("demo_scene1");
    expect(tailText("a".repeat(24), 24)).toBe("a".repeat(24));
  });

  it("路径类值保留最后两段（/ 分隔）", () => {
    expect(tailText("Resources/image/生成电影概念图.png")).toBe("…/image/生成电影概念图.png");
    expect(tailText("a/very/long/path/segment/end.txt")).toBe("…/segment/end.txt");
  });

  it("反斜杠与下划线同样视作分段", () => {
    expect(tailText("Resources\\audio\\demo_bgm_final_take_2.wav")).toBe(
      "…\\audio\\demo_bgm_final_take_2.wav",
    );
    expect(tailText("prefix_middle_last_segment_name")).toBe("…_segment_name");
  });

  it("普通超长串保留尾部 max 字符", () => {
    const s = "x".repeat(40);
    expect(tailText(s, 10)).toBe("…" + "x".repeat(10));
  });

  it("仅一个分隔符时按普通串处理", () => {
    const s = "a/" + "b".repeat(40);
    expect(tailText(s, 20)).toBe("…" + "b".repeat(20));
  });
});
