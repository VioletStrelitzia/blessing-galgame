// 确定性 AABB 防重叠分离（纯视图层）：迭代松弛，把重叠节点沿最小重叠轴推开。
// 选型说明：不用 d3-force（模拟式、非确定、依赖 tick 生命周期）——有向 TB 流程图要的是
// 「确定、可测、一次到位」的推挤语义：同输入必同输出，单测可断言，无副作用可挂在任何事件后。

import type { Pos } from "./layout";

export interface CollideRect {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 分离后的节点间最小净距 */
export const COLLIDE_GAP = 16;
/** 位移写入阈值：小于该值视为未动（防抖动回环） */
const EPS = 0.5;

export interface SeparateOptions {
  gap?: number;
  /** 钉住的节点不移动（如拖动中的节点）；双方都钉住的重叠对跳过 */
  pinned?: ReadonlySet<string>;
  maxIter?: number;
}

/**
 * 重叠分离：返回需位移节点的 id → 新左上角位置（仅含位移 > EPS 者；入参不动）。
 * 规则：按输入序遍历全部矩形对；重叠时沿较小重叠轴分离（平手取 y，顺应 TB 流向）；
 * 双方都未钉住各承担一半位移，恰一方钉住则另一方承担全部。
 * 每轮全扫一遍，整轮无位移即收敛；maxIter 兜底。
 */
export function separateOverlaps(
  rects: CollideRect[],
  opts: SeparateOptions = {},
): Map<string, Pos> {
  const gap = opts.gap ?? COLLIDE_GAP;
  const pinned = opts.pinned ?? new Set<string>();
  const maxIter = opts.maxIter ?? 100;

  const items = rects.map((r) => ({
    id: r.id,
    cx: r.x + r.w / 2,
    cy: r.y + r.h / 2,
    w: r.w,
    h: r.h,
    pin: pinned.has(r.id),
  }));

  for (let iter = 0; iter < maxIter; iter++) {
    let moved = false;
    for (let i = 0; i < items.length; i++) {
      for (let j = i + 1; j < items.length; j++) {
        const a = items[i];
        const b = items[j];
        const ox = (a.w + b.w) / 2 + gap - Math.abs(a.cx - b.cx);
        if (ox <= 0) continue;
        const oy = (a.h + b.h) / 2 + gap - Math.abs(a.cy - b.cy);
        if (oy <= 0) continue;
        if (a.pin && b.pin) continue;
        // 沿较小重叠轴分离；平手取 y（流程方向）
        const axis: "x" | "y" = oy <= ox ? "y" : "x";
        const overlap = axis === "y" ? oy : ox;
        const diff = axis === "y" ? b.cy - a.cy : b.cx - a.cx;
        const dir = diff >= 0 ? 1 : -1;
        const shareA = a.pin ? 0 : b.pin ? 1 : 0.5;
        const shareB = b.pin ? 0 : a.pin ? 1 : 0.5;
        if (axis === "y") {
          a.cy -= dir * overlap * shareA;
          b.cy += dir * overlap * shareB;
        } else {
          a.cx -= dir * overlap * shareA;
          b.cx += dir * overlap * shareB;
        }
        moved = true;
      }
    }
    if (!moved) break;
  }

  const out = new Map<string, Pos>();
  for (let i = 0; i < items.length; i++) {
    const nx = items[i].cx - items[i].w / 2;
    const ny = items[i].cy - items[i].h / 2;
    if (Math.abs(nx - rects[i].x) > EPS || Math.abs(ny - rects[i].y) > EPS) {
      out.set(items[i].id, { x: nx, y: ny });
    }
  }
  return out;
}
