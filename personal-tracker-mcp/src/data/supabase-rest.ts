import { AuthError, refreshSession, type GoTrueConfig, type Session } from "../auth/supabase-auth";

export interface SessionStore {
  get(): Session;
  set(s: Session): void | Promise<void>;
}

export interface SupabaseRest {
  list(table: string, opts?: { eq?: Record<string, string>; order?: string; limit?: number }): Promise<any[]>;
  get(table: string, id: string): Promise<any | null>;
  insert(table: string, row: Record<string, unknown>): Promise<any>;
  patch(table: string, id: string, changes: Record<string, unknown>): Promise<any | null>;
}

export class RestError extends Error {}

const REFRESH_SKEW_SECONDS = 60;
const LIMIT_DEFAULT = 100;
const LIMIT_MAX = 500;

export function makeSupabaseRest(cfg: GoTrueConfig, store: SessionStore): SupabaseRest {
  async function bearer(): Promise<string> {
    let s = store.get();
    if (s.expiresAt - Math.floor(Date.now() / 1000) < REFRESH_SKEW_SECONDS) {
      try {
        s = await refreshSession(cfg, s.refreshToken);
        await store.set(s);
      } catch {
        throw new AuthError("SESSION_EXPIRED");
      }
    }
    return s.accessToken;
  }

  async function req(method: string, pathAndQuery: string, body?: unknown): Promise<any[]> {
    const token = await bearer();
    const send = () =>
      fetch(`${cfg.url}/rest/v1/${pathAndQuery}`, {
        method,
        headers: {
          apikey: cfg.anonKey,
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });

    let res = await send();
    if (res.status >= 500) {
      await new Promise((r) => setTimeout(r, 500));
      res = await send();
    }
    if (!res.ok) {
      if (res.status === 401) throw new AuthError("SESSION_EXPIRED");
      const err = (await res.json().catch(() => ({}))) as { message?: string; hint?: string };
      throw new RestError(
        `Supabase rejected the request (${res.status}): ${err.message || err.hint || res.statusText}`,
      );
    }
    if (res.status === 204) return [];
    return (await res.json()) as any[];
  }

  return {
    async list(table, opts = {}) {
      const q = new URLSearchParams();
      q.set("select", "*");
      q.set("is_deleted", "eq.false");
      for (const [k, v] of Object.entries(opts.eq ?? {})) q.set(k, `eq.${v}`);
      if (opts.order) q.set("order", opts.order);
      q.set("limit", String(Math.min(opts.limit ?? LIMIT_DEFAULT, LIMIT_MAX)));
      return req("GET", `${table}?${q.toString()}`);
    },
    async get(table, id) {
      const rows = await req("GET", `${table}?id=eq.${encodeURIComponent(id)}&select=*&limit=1`);
      return rows[0] ?? null;
    },
    async insert(table, row) {
      const rows = await req("POST", table, [row]);
      return rows[0] ?? row;
    },
    async patch(table, id, changes) {
      const rows = await req("PATCH", `${table}?id=eq.${encodeURIComponent(id)}`, changes);
      return rows[0] ?? null;
    },
  };
}
