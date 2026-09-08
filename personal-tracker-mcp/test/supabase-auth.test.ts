import { afterEach, describe, expect, test, vi } from "vitest";
import { AuthError, refreshSession, signInWithPassword } from "../src/auth/supabase-auth";

const cfg = { url: "https://x.supabase.co", anonKey: "anon" };
const goodBody = {
  access_token: "at", refresh_token: "rt", expires_at: 1893456000,
  user: { id: "user-1", email: "me@example.com" },
};

afterEach(() => vi.unstubAllGlobals());

function stubFetch(status: number, body: unknown) {
  // Fresh Response per call — a Response body can only be read once.
  const fn = vi.fn().mockImplementation(() =>
    Promise.resolve(
      new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
    ),
  );
  vi.stubGlobal("fetch", fn);
  return fn;
}

describe("signInWithPassword", () => {
  test("maps a successful GoTrue token to a Session", async () => {
    const fetchFn = stubFetch(200, goodBody);
    const s = await signInWithPassword(cfg, "me@example.com", "pw");
    expect(s).toEqual({
      supabaseUserId: "user-1", email: "me@example.com",
      accessToken: "at", refreshToken: "rt", expiresAt: 1893456000,
    });
    const [url, init] = fetchFn.mock.calls[0];
    expect(String(url)).toBe("https://x.supabase.co/auth/v1/token?grant_type=password");
    expect((init as RequestInit).method).toBe("POST");
    expect((init!.headers as Record<string, string>).apikey).toBe("anon");
  });

  test("throws AuthError with GoTrue's message on 400", async () => {
    stubFetch(400, { error_description: "Invalid login credentials" });
    await expect(signInWithPassword(cfg, "me@example.com", "bad")).rejects.toThrowError(AuthError);
    await expect(signInWithPassword(cfg, "me@example.com", "bad")).rejects.toThrow("Invalid login credentials");
  });
});

describe("refreshSession", () => {
  test("returns a fresh Session on success", async () => {
    stubFetch(200, { ...goodBody, access_token: "at2", refresh_token: "rt2" });
    const s = await refreshSession(cfg, "rt");
    expect(s.accessToken).toBe("at2");
    expect(s.refreshToken).toBe("rt2");
  });
  test("throws AuthError('SESSION_EXPIRED') on failure", async () => {
    stubFetch(401, { error: "invalid_grant" });
    await expect(refreshSession(cfg, "rt")).rejects.toThrow("SESSION_EXPIRED");
  });
});
