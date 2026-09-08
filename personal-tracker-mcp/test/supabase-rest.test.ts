import { afterEach, describe, expect, test, vi } from "vitest";
import { AuthError, type Session } from "../src/auth/supabase-auth";
import { makeSupabaseRest } from "../src/data/supabase-rest";

const cfg = { url: "https://x.supabase.co", anonKey: "anon" };
const future = Math.floor(Date.now() / 1000) + 3600;

function store(overrides: Partial<Session> = {}) {
  let s: Session = {
    supabaseUserId: "u1", email: "e", accessToken: "at", refreshToken: "rt",
    expiresAt: future, ...overrides,
  };
  return { get: () => s, set: vi.fn(async (n: Session) => { s = n; }), _peek: () => s };
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

afterEach(() => vi.unstubAllGlobals());

describe("makeSupabaseRest", () => {
  test("list builds the URL: select, is_deleted filter, eq filters, clamped limit", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const rows = await rest.list("transactions", { eq: { type: "expense" }, limit: 9999 });
    expect(rows).toEqual([{ id: "1" }]);
    const url = new URL(String(fetchFn.mock.calls[0][0]));
    expect(url.pathname).toBe("/rest/v1/transactions");
    expect(url.searchParams.get("select")).toBe("*");
    expect(url.searchParams.get("is_deleted")).toBe("eq.false");
    expect(url.searchParams.get("type")).toBe("eq.expense");
    expect(url.searchParams.get("limit")).toBe("500");
    const headers = (fetchFn.mock.calls[0][1] as RequestInit).headers as Record<string, string>;
    expect(headers.apikey).toBe("anon");
    expect(headers.Authorization).toBe("Bearer at");
  });

  test("get returns the first row, or null when empty", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(200, [])));
    const rest = makeSupabaseRest(cfg, store());
    expect(await rest.get("accounts", "abc")).toBeNull();
  });

  test("insert POSTs an array and returns the representation row", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(201, [{ id: "new", name: "HDFC" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const row = await rest.insert("accounts", { id: "new", name: "HDFC" });
    expect(row).toEqual({ id: "new", name: "HDFC" });
    const init = fetchFn.mock.calls[0][1] as RequestInit;
    expect(init.method).toBe("POST");
    expect(JSON.parse(String(init.body))).toEqual([{ id: "new", name: "HDFC" }]);
    expect((init.headers as Record<string, string>).Prefer).toContain("return=representation");
  });

  test("patch targets id=eq.<id> and returns the row", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(200, [{ id: "x", is_deleted: true }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const row = await rest.patch("goals", "x", { is_deleted: true });
    expect(row).toEqual({ id: "x", is_deleted: true });
    const url = new URL(String(fetchFn.mock.calls[0][0]));
    expect(url.searchParams.get("id")).toBe("eq.x");
    expect((fetchFn.mock.calls[0][1] as RequestInit).method).toBe("PATCH");
  });

  test("refreshes the token when the session is within 60s of expiry", async () => {
    const near = Math.floor(Date.now() / 1000) + 30;
    const s = store({ expiresAt: near });
    const fetchFn = vi.fn()
      .mockResolvedValueOnce(json(200, {
        access_token: "at2", refresh_token: "rt2", expires_at: future,
        user: { id: "u1", email: "e" },
      }))
      .mockResolvedValueOnce(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, s);
    await rest.list("accounts");
    expect(s.set).toHaveBeenCalledOnce();
    expect(s._peek().accessToken).toBe("at2");
    expect((fetchFn.mock.calls[1][1] as RequestInit).headers as Record<string, string>).toMatchObject({ Authorization: "Bearer at2" });
  });

  test("retries once on a 5xx then succeeds", async () => {
    const fetchFn = vi.fn()
      .mockResolvedValueOnce(json(503, { message: "upstream" }))
      .mockResolvedValueOnce(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    expect(await rest.list("loans")).toEqual([{ id: "1" }]);
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });

  test("maps a 401 to AuthError", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(401, { message: "JWT expired" })));
    const rest = makeSupabaseRest(cfg, store());
    await expect(rest.list("loans")).rejects.toThrowError(AuthError);
  });
});
