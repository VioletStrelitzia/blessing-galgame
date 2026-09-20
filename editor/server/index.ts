// BGalS 编辑器伴随服务：/api/* 数据桥（fixtures 离线 / live 经引擎 CLI），生产模式托管 dist。
// --dev 或 BGALS_DEV=1 时额外注册 /api/dev/* 调试桥。

import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { Hono, type Context } from "hono";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { registerDevRoutes } from "./dev";
import { createFixturesSource, EDITOR_ROOT, HttpError, type Source } from "./fixtures";
import { createLiveSource } from "./godot";

const PORT = Number(process.env.BGALS_PORT ?? 8787);
const SCRIPT_NAME = /^[\w-]+$/;
const NEW_SCRIPT_NAME = /^[a-zA-Z][a-zA-Z0-9_]*$/;

const fixturesMode = process.argv.includes("--fixtures") || process.env.BGALS_FIXTURES === "1";
const devMode = process.argv.includes("--dev") || process.env.BGALS_DEV === "1";
const source: Source = fixturesMode ? createFixturesSource() : createLiveSource();

const app = new Hono();

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message }, 500);
});

/** HttpError → 对应状态码；其余抛给 onError */
async function respond(c: Context, fn: () => Promise<unknown>) {
  try {
    return c.json(await fn());
  } catch (err) {
    if (err instanceof HttpError) return c.json({ error: err.message }, err.status);
    throw err;
  }
}

app.get("/api/spec", async (c) => c.json(await source.spec()));
app.get("/api/mode", (c) => c.json({ mode: fixturesMode ? "fixtures" : "live", dev: devMode }));
app.get("/api/graphs", async (c) => c.json(await source.listGraphs()));
app.get("/api/graph/:script", async (c) => {
  const script = c.req.param("script");
  if (!SCRIPT_NAME.test(script)) return c.json({ error: `非法剧本名: ${script}` }, 400);
  const graph = await source.graph(script);
  if (graph === null) return c.json({ error: `剧本不存在: ${script}` }, 404);
  return c.json(graph);
});
app.post("/api/check", async (c) => c.json(await source.check()));
app.get("/api/refs", async (c) => c.json(await source.refs()));
app.get("/api/overview", async (c) => c.json(await source.overview()));

app.get("/api/script/:script/sidecar", async (c) => {
  const script = c.req.param("script");
  if (!SCRIPT_NAME.test(script)) return c.json({ error: `非法剧本名: ${script}` }, 400);
  const sidecar = await source.sidecar(script);
  if (sidecar === null) return c.json({ error: `sidecar 不存在: ${script}` }, 404);
  return c.json(sidecar);
});

app.post("/api/script/:script/save", async (c) => {
  const script = c.req.param("script");
  if (!SCRIPT_NAME.test(script)) return c.json({ error: `非法剧本名: ${script}` }, 400);
  const body = await c.req.json<{ text?: unknown; sidecar?: unknown }>();
  if (typeof body.text !== "string")
    return c.json({ error: "body 缺少 string 类型 text 字段" }, 400);
  return respond(c, () => source.save(script, body.text as string, body.sidecar));
});

app.post("/api/script/new", async (c) => {
  const body = await c.req.json<{ name?: unknown }>();
  const name = typeof body.name === "string" ? body.name : "";
  if (!NEW_SCRIPT_NAME.test(name)) return c.json({ error: `非法剧本名: ${name}` }, 400);
  if (name === "main_menu") return c.json({ error: "main_menu 为保留名，不可新建" }, 400);
  return respond(c, () => source.createScript(name));
});

if (devMode) registerDevRoutes(app);

// 生产模式：托管前端构建产物（SPA 回退 index.html）
const dist = path.join(EDITOR_ROOT, "dist");
const indexHtml = path.join(dist, "index.html");
if (!fixturesMode && existsSync(indexHtml)) {
  app.use("/*", serveStatic({ root: dist }));
  app.get("*", (c) => {
    if (c.req.path.startsWith("/api/")) return c.json({ error: "not found" }, 404);
    return c.html(readFileSync(indexHtml, "utf8"));
  });
}

serve({ fetch: app.fetch, port: PORT }, (info) => {
  console.log(
    `[bgals-editor] mode=${fixturesMode ? "fixtures" : "live"} dev=${devMode} port=${info.port}`,
  );
});
