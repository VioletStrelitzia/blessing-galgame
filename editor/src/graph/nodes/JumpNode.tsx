import { Handle, Position, type NodeProps } from "@xyflow/react";
import { MAIN_MENU } from "../../../shared/overview";
import { TailText } from "../../components/TailText";
import { openScript } from "../../state/io";
import type { FlowNode } from "../toFlow";
import { NodeShell } from "./shell";

export function JumpNode({ data, selected }: NodeProps<FlowNode>) {
  if (data.node.kind !== "jump") return null;
  const target = data.node.target;
  const isMainMenu = target === MAIN_MENU;
  return (
    <NodeShell kind="jump" selected={selected} diags={data.diags}>
      <Handle type="target" position={Position.Top} />
      <div
        className="flex font-mono text-xs"
        title={isMainMenu ? "主菜单终态（不可跳转）" : `双击打开剧本 ${target}`}
        onDoubleClick={(e) => {
          e.stopPropagation();
          if (!isMainMenu) void openScript(target);
        }}
      >
        <span className="mr-1 shrink-0 text-dim">→</span>
        <TailText
          text={target}
          max={24}
          className={`overflow-hidden ${isMainMenu ? "text-warn" : "text-danger"}`}
        />
      </div>
    </NodeShell>
  );
}
