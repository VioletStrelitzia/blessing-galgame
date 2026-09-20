import { describe, expect, it } from "vitest";
import { COLLIDE_GAP, separateOverlaps, type CollideRect } from "./collide";

function rect(id: string, x: number, y: number, w = 100, h = 50): CollideRect {
  return { id, x, y, w, h };
}

function gap(a: CollideRect, b: CollideRect): { ox: number; oy: number } {
  const acx = a.x + a.w / 2;
  const acy = a.y + a.h / 2;
  const bcx = b.x + b.w / 2;
  const bcy = b.y + b.h / 2;
  return {
    ox: (a.w + b.w) / 2 - Math.abs(acx - bcx),
    oy: (a.h + b.h) / 2 - Math.abs(acy - bcy),
  };
}

describe("separateOverlaps", () => {
  it("无重叠 → 空结果", () => {
    const rects = [rect("a", 0, 0), rect("b", 0, 200), rect("c", 400, 0)];
    expect(separateOverlaps(rects).size).toBe(0);
  });

  it("垂直重叠（同 x 纵链）→ 沿 y 各走一半，分离后净距 = gap", () => {
    const rects = [rect("a", 0, 0, 100, 100), rect("b", 0, 60, 100, 100)];
    const moved = separateOverlaps(rects);
    const a = { ...rects[0], ...moved.get("a") };
    const b = { ...rects[1], ...moved.get("b") };
    // a 在上保持相对顺序，b 被推到 a 下方 gap 处
    expect(a.y).toBeLessThan(b.y);
    expect(b.y - (a.y + a.h)).toBeCloseTo(COLLIDE_GAP, 3);
    // 对称：位移量相等（初始重叠 40 + gap 16 = 56，各 28）
    expect(moved.get("a")!.y).toBeCloseTo(0 - 28, 3);
    expect(moved.get("b")!.y).toBeCloseTo(60 + 28, 3);
  });

  it("水平重叠更小 → 沿 x 分离", () => {
    const rects = [rect("a", 0, 0, 200, 50), rect("b", 190, 0, 200, 50)];
    const moved = separateOverlaps(rects);
    const a = { ...rects[0], ...moved.get("a") };
    const b = { ...rects[1], ...moved.get("b") };
    expect(b.x - (a.x + a.w)).toBeCloseTo(COLLIDE_GAP, 3);
    // 沿 x 分离，y 不动
    expect(moved.get("a")!.y).toBe(0);
    expect(moved.get("b")!.y).toBe(0);
  });

  it("pinned 不动，另一方承担全部位移", () => {
    const rects = [rect("a", 0, 0, 100, 100), rect("b", 0, 60, 100, 100)];
    const moved = separateOverlaps(rects, { pinned: new Set(["a"]) });
    expect(moved.has("a")).toBe(false);
    const b = { ...rects[1], ...moved.get("b") };
    expect(b.y - (0 + 100)).toBeCloseTo(COLLIDE_GAP, 3);
  });

  it("双方都 pinned → 跳过（保持重叠也不动）", () => {
    const rects = [rect("a", 0, 0), rect("b", 0, 10)];
    const moved = separateOverlaps(rects, { pinned: new Set(["a", "b"]) });
    expect(moved.size).toBe(0);
  });

  it("链式传递：压入顶部分叉处，下游被级联推开", () => {
    // a 与 b 重叠，b 与 c 紧邻（推开 b 会压到 c → c 也被推走）
    const rects = [
      rect("a", 0, 0, 100, 100),
      rect("b", 0, 60, 100, 100),
      rect("c", 0, 170, 100, 100),
    ];
    const moved = separateOverlaps(rects);
    const pos = new Map(rects.map((r) => [r.id, { ...r, ...moved.get(r.id) }]));
    const ab = gap(pos.get("a")! as CollideRect, pos.get("b")! as CollideRect);
    const bc = gap(pos.get("b")! as CollideRect, pos.get("c")! as CollideRect);
    expect(ab.oy).toBeLessThanOrEqual(-COLLIDE_GAP + 0.01);
    expect(bc.oy).toBeLessThanOrEqual(-COLLIDE_GAP + 0.01);
    // 顺序保持
    expect(pos.get("a")!.y).toBeLessThan(pos.get("b")!.y);
    expect(pos.get("b")!.y).toBeLessThan(pos.get("c")!.y);
  });

  it("确定性：同一输入两次调用结果完全一致", () => {
    const rects = [
      rect("a", 0, 0, 120, 90),
      rect("b", 30, 40, 100, 120),
      rect("c", -50, 100, 200, 60),
      rect("d", 200, 20, 80, 80),
    ];
    const r1 = separateOverlaps(rects);
    const r2 = separateOverlaps(rects);
    expect([...r1.entries()]).toEqual([...r2.entries()]);
  });

  it("不同尺寸混合 + 四周包围 → 收敛无重叠", () => {
    const rects = [
      rect("c", 0, 0, 60, 60),
      rect("n", -20, -80, 100, 60),
      rect("s", -10, 30, 100, 90),
      rect("e", 40, -10, 90, 60),
      rect("w", -90, -5, 60, 60),
    ];
    const moved = separateOverlaps(rects);
    const pos = rects.map((r) => ({ ...r, ...moved.get(r.id) }));
    for (let i = 0; i < pos.length; i++) {
      for (let j = i + 1; j < pos.length; j++) {
        const { ox, oy } = gap(pos[i], pos[j]);
        expect(Math.min(ox, oy)).toBeLessThanOrEqual(-COLLIDE_GAP + 0.01);
      }
    }
  });
});
