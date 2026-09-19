import type { CheckReport } from "../shared/check";
import type { BgalsGraph } from "../shared/graph";
import type { Sidecar } from "../shared/sidecar";
import type { BgalsSpec } from "../shared/spec";

/** 携带 HTTP 状态码与服务端 error 文案的错误（403 只读、404 sidecar 缺失等） */
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) {
    let msg = `${url} → HTTP ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) msg = body.error;
    } catch {
      // 非 JSON 错误体：保留状态码文案
    }
    throw new ApiError(res.status, msg);
  }
  return (await res.json()) as T;
}

function post<T>(url: string, body?: unknown): Promise<T> {
  return request<T>(url, {
    method: "POST",
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/** index.json 资源索引：域（audio/texture/script）→ key → 路径 */
export type RefsData = Record<string, Record<string, string>>;

export interface ModeInfo {
  mode: "fixtures" | "live";
  dev: boolean;
}

export const api = {
  spec: () => request<BgalsSpec>("/api/spec"),
  mode: () => request<ModeInfo>("/api/mode"),
  graphs: () => request<{ script: string }[]>("/api/graphs"),
  graph: (script: string) => request<BgalsGraph>(`/api/graph/${encodeURIComponent(script)}`),
  check: () => post<CheckReport>("/api/check"),
  refs: () => request<RefsData>("/api/refs"),
  /** sidecar 404（尚未保存过布局）容忍为 null */
  async sidecar(script: string): Promise<Sidecar | null> {
    try {
      return await request<Sidecar>(`/api/script/${encodeURIComponent(script)}/sidecar`);
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) return null;
      throw e;
    }
  },
  save: (script: string, text: string, sidecar: Sidecar) =>
    post<{ ok: boolean; script: string; path: string }>(
      `/api/script/${encodeURIComponent(script)}/save`,
      { text, sidecar },
    ),
  createScript: (name: string) => post<{ script: string }>("/api/script/new", { name }),
  devEnabled: () => request<{ enabled: boolean }>("/api/dev/enabled"),
  devResult: (id: string, ok: boolean, data: unknown) =>
    post<{ ok: boolean }>("/api/dev/result", ok ? { id, ok, data } : { id, ok, message: data }),
};
