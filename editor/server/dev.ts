// 调试桥（仅 --dev 或 BGALS_DEV=1 时注册）：编辑器前端 ↔ 运行中引擎实例的命令通道。
// /api/dev/events 为 SSE 下行流（命令广播 + 15s 心跳）；前端执行结果经 /api/dev/result 回传，
// 解除 /api/dev/command 的挂起等待（10s 超时退 504）。

import type { Context, Hono } from "hono";
import { streamSSE, type SSEStreamingApi } from "hono/streaming";
import { nanoid } from "nanoid";

const COMMAND_TIMEOUT_MS = 10_000;
const HEARTBEAT_MS = 15_000;

interface Pending {
  resolve: (result: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

export function registerDevRoutes(app: Hono): void {
  const clients = new Set<SSEStreamingApi>();
  const pending = new Map<string, Pending>();

  app.get("/api/dev/enabled", (c) => c.json({ enabled: true }));

  app.get("/api/dev/events", (c) =>
    streamSSE(c, async (stream) => {
      clients.add(stream);
      stream.onAbort(() => {
        clients.delete(stream);
      });
      for (;;) {
        await stream.writeSSE({ event: "ping", data: "{}" });
        await stream.sleep(HEARTBEAT_MS);
      }
    }),
  );

  app.post("/api/dev/command", async (c: Context) => {
    const body = await c.req.json<{ id?: string; action?: string; args?: unknown }>();
    if (!body.action) return c.json({ error: "body 缺少 action 字段" }, 400);
    const id = body.id ?? nanoid(10);
    const message = JSON.stringify({ id, action: body.action, args: body.args ?? null });
    const result = new Promise<unknown>((resolve) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        resolve(null);
      }, COMMAND_TIMEOUT_MS);
      pending.set(id, { resolve, timer });
    });
    for (const stream of clients) {
      await stream.writeSSE({ event: "command", data: message });
    }
    const out = await result;
    if (out === null) return c.json({ error: "等待浏览器响应超时（10s）" }, 504);
    return c.json(out);
  });

  app.post("/api/dev/result", async (c: Context) => {
    const body = await c.req.json<{ id?: string; ok?: boolean; data?: unknown }>();
    const p = body.id === undefined ? undefined : pending.get(body.id);
    if (!p || body.id === undefined) return c.json({ error: "无匹配等待中的命令" }, 404);
    clearTimeout(p.timer);
    pending.delete(body.id);
    p.resolve(body);
    return c.json({ ok: true });
  });
}
