import { create } from "zustand";
import type { CheckReport } from "../shared/check";
import type { BgalsGraph } from "../shared/graph";
import type { BgalsSpec } from "../shared/spec";
import { api } from "./api";

interface EditorState {
  spec: BgalsSpec | null;
  scripts: string[];
  current: string | null;
  graph: BgalsGraph | null;
  report: CheckReport | null;
  selected: string | null;
  checking: boolean;
  error: string | null;
  init(): Promise<void>;
  openScript(script: string): Promise<void>;
  runCheck(): Promise<void>;
  select(id: string | null): void;
}

export const useEditor = create<EditorState>((set, get) => ({
  spec: null,
  scripts: [],
  current: null,
  graph: null,
  report: null,
  selected: null,
  checking: false,
  error: null,
  async init() {
    try {
      const [spec, graphs] = await Promise.all([api.spec(), api.graphs()]);
      set({ spec, scripts: graphs.map((g) => g.script) });
      const first = graphs[0];
      if (first) await get().openScript(first.script);
    } catch (e) {
      set({ error: (e as Error).message });
    }
  },
  async openScript(script) {
    try {
      const graph = await api.graph(script);
      set({ graph, current: script, selected: null });
    } catch (e) {
      set({ error: (e as Error).message });
    }
  },
  async runCheck() {
    set({ checking: true });
    try {
      const report = await api.check();
      set({ report, checking: false });
    } catch (e) {
      set({ checking: false, error: (e as Error).message });
    }
  },
  select(id) {
    set({ selected: id });
  },
}));
