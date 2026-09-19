import type { CheckReport } from "../shared/check";
import type { BgalsGraph } from "../shared/graph";
import type { BgalsSpec } from "../shared/spec";

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
  return (await res.json()) as T;
}

export const api = {
  spec: () => request<BgalsSpec>("/api/spec"),
  graphs: () => request<{ script: string }[]>("/api/graphs"),
  graph: (script: string) => request<BgalsGraph>(`/api/graph/${encodeURIComponent(script)}`),
  check: () => request<CheckReport>("/api/check", { method: "POST" }),
};
