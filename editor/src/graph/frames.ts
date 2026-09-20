// 展开聚合链的边界框（Archify 分组框）：成员位置包围盒 + padding，纯视图计算。
// 组收起时无 frame；frame 不参与聚合、不入 sidecar、不进 flowNeighbor/emit/compare。

import type { GraphNode } from "../../shared/graph";
import { groupIdOf } from "./collapse";
import { estimateSizeFor, type Pos } from "./layout";

export const FRAME_PAD_X = 24;
export const FRAME_PAD_TOP = 44; // 含左上角标签位
export const FRAME_PAD_BOTTOM = 24;

export interface FrameRect {
  groupId: string;
  groupKind: string;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

/** 展开中的链 → frame 矩形（成员位置缺失的链跳过；返回仅含展开集内的链）。
 *  sizes 为 FlowCanvas 实测尺寸（DOM 测量，缺省回退 estimateSizeFor 估算） */
export function frameRects(
  runs: GraphNode[][],
  expanded: Set<string>,
  positions: Map<string, Pos>,
  sizes?: Map<string, { w: number; h: number }>,
): FrameRect[] {
  const out: FrameRect[] = [];
  for (const run of runs) {
    const groupId = groupIdOf(run[0].id);
    if (!expanded.has(groupId)) continue;
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const n of run) {
      const p = positions.get(n.id);
      if (!p) continue;
      const sz = sizes?.get(n.id);
      const est = sz ? null : estimateSizeFor(n.kind, 0);
      const w = sz ? sz.w : est!.width;
      const h = sz ? sz.h : est!.height;
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + w);
      maxY = Math.max(maxY, p.y + h);
    }
    if (!Number.isFinite(minX)) continue;
    out.push({
      groupId,
      groupKind: run[0].kind,
      label: `${run[0].kind.toUpperCase()} ×${run.length}`,
      x: minX - FRAME_PAD_X,
      y: minY - FRAME_PAD_TOP,
      width: maxX - minX + FRAME_PAD_X * 2,
      height: maxY - minY + FRAME_PAD_TOP + FRAME_PAD_BOTTOM,
    });
  }
  return out;
}
