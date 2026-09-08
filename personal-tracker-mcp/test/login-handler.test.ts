import { afterEach, describe, expect, test, vi } from "vitest";
import { loginApp } from "../src/auth/login-handler";

const authReq = { clientId: "c1", redirectUri: "https://claude.ai/cb", scope: ["personal-tracker"], state: "s1" };

function env(overrides: Record<string, unknown> = {}) {
  return {
    SUPABASE_URL: "https://x.supabase.co",
    SUPABASE_ANON_KEY: "anon",
    OAUTH_PROVIDER: {
      parseAuthRequest: vi.fn().mockResolvedValue(authReq),
      lookupClient: vi.fn().mockResolvedValue({ clientId: "c1" }),
      completeAuthorization: vi.fn().mockResolvedValue({ redirectTo: "https://claude.ai/cb?code=abc&state=s1" }),
    },
    ...overrides,
  };
}

function goTrue(status: number, body: unknown) {
  vi.stubGlobal("fetch", vi.fn().mockImplementation(() =>
    Promise.resolve(new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } })),
  ));
}

afterEach(() => vi.unstubAllGlobals());

describe("GET /authorize", () => {
  test("renders a form carrying the serialized auth request", async () => {
    const e = env();
    const res = await loginApp.request("https://mcp.example/authorize?client_id=c1", {}, e);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('name="email"');
    expect(body).toContain('name="password"');
    expect(body).toContain('name="auth_request"');
    expect(e.OAUTH_PROVIDER.parseAuthRequest).toHaveBeenCalled();
  });
});

describe("POST /authorize", () => {
  test("valid credentials complete the grant and 302 to redirectTo", async () => {
    const e = env();
    goTrue(200, { access_token: "at", refresh_token: "rt", expires_at: 1893456000, user: { id: "u1", email: "me@x.com" } });
    const form = new URLSearchParams({ email: "me@x.com", password: "pw", auth_request: JSON.stringify(authReq) });
    const res = await loginApp.request("https://mcp.example/authorize", {
      method: "POST", body: form, headers: { "content-type": "application/x-www-form-urlencoded" },
    }, e);
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("https://claude.ai/cb?code=abc&state=s1");
    const arg = e.OAUTH_PROVIDER.completeAuthorization.mock.calls[0][0];
    expect(arg.userId).toBe("u1");
    expect(arg.props).toMatchObject({ accessToken: "at", refreshToken: "rt", email: "me@x.com" });
  });

  test("bad credentials re-render the form with an error and 401", async () => {
    const e = env();
    goTrue(400, { error_description: "Invalid login credentials" });
    const form = new URLSearchParams({ email: "me@x.com", password: "bad", auth_request: JSON.stringify(authReq) });
    const res = await loginApp.request("https://mcp.example/authorize", {
      method: "POST", body: form, headers: { "content-type": "application/x-www-form-urlencoded" },
    }, e);
    expect(res.status).toBe(401);
    const body = await res.text();
    expect(body).toContain("Invalid login credentials");
    expect(body).toContain('name="password"');
    expect(e.OAUTH_PROVIDER.completeAuthorization).not.toHaveBeenCalled();
  });
});

test("unknown path 404s", async () => {
  const res = await loginApp.request("https://mcp.example/nope", {}, env());
  expect(res.status).toBe(404);
});
