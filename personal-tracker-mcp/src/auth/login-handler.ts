import { Hono } from "hono";
import { html, raw } from "hono/html";
import { AuthError, signInWithPassword } from "./supabase-auth";
import type { Env } from "../types";

interface OAuthHelpers {
  parseAuthRequest(request: Request): Promise<any>;
  lookupClient(clientId: string): Promise<unknown | null>;
  completeAuthorization(opts: {
    request: any;
    userId: string;
    metadata?: Record<string, unknown>;
    scope: string[];
    props: Record<string, unknown>;
  }): Promise<{ redirectTo: string }>;
}

type Bindings = Env & { OAUTH_PROVIDER: OAuthHelpers };

export const loginApp = new Hono<{ Bindings: Bindings }>();

loginApp.get("/authorize", async (c) => {
  let authRequest: any;
  try {
    authRequest = await c.env.OAUTH_PROVIDER.parseAuthRequest(c.req.raw);
  } catch (e: any) {
    return c.text(e?.description ?? "Invalid authorization request", 400);
  }
  const client = await c.env.OAUTH_PROVIDER.lookupClient(authRequest.clientId);
  if (!client) return c.text("Unknown client", 400);
  return c.html(page(JSON.stringify(authRequest)));
});

loginApp.post("/authorize", async (c) => {
  const form = await c.req.formData();
  const email = String(form.get("email") ?? "");
  const password = String(form.get("password") ?? "");
  const rawAuth = String(form.get("auth_request") ?? "{}");

  let authRequest: any;
  try {
    authRequest = JSON.parse(rawAuth);
  } catch {
    return c.text("Malformed authorization request", 400);
  }

  try {
    const session = await signInWithPassword(
      { url: c.env.SUPABASE_URL, anonKey: c.env.SUPABASE_ANON_KEY },
      email,
      password,
    );
    const { redirectTo } = await c.env.OAUTH_PROVIDER.completeAuthorization({
      request: authRequest,
      userId: session.supabaseUserId,
      metadata: { email: session.email },
      scope: Array.isArray(authRequest.scope) ? authRequest.scope : ["personal-tracker"],
      props: { ...session },
    });
    return c.redirect(redirectTo, 302);
  } catch (e) {
    const msg = e instanceof AuthError ? e.message : "Sign-in failed. Please try again.";
    return c.html(page(rawAuth, msg), 401);
  }
});

loginApp.all("*", (c) => c.text("Not found", 404));

function page(authRequestJson: string, error?: string) {
  return html`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Connect PersonalTracker</title>
<style>
  body { font: 16px/1.5 system-ui, -apple-system, sans-serif; background: #0f1117;
    color: #e8eaed; display: grid; place-items: center; min-height: 100vh; margin: 0; }
  form { background: #1a1d27; padding: 32px; border-radius: 16px; width: min(360px, 92vw);
    box-shadow: 0 8px 40px rgba(0,0,0,.45); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  p.sub { margin: 0 0 20px; color: #9aa0a6; font-size: 14px; }
  label { display: block; font-size: 13px; margin: 14px 0 4px; color: #c7c9d1; }
  input { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 8px;
    border: 1px solid #333747; background: #0f1117; color: #e8eaed; font-size: 15px; }
  button { margin-top: 22px; width: 100%; padding: 11px; border: 0; border-radius: 8px;
    background: #4f7cff; color: #fff; font-size: 15px; font-weight: 600; cursor: pointer; }
  .err { margin-top: 14px; color: #ff6b6b; font-size: 13px; }
</style></head><body>
<form method="post" action="/authorize">
  <h1>Connect PersonalTracker</h1>
  <p class="sub">Sign in with your PersonalTracker (Aspyric) account.</p>
  <label for="email">Email</label>
  <input id="email" name="email" type="email" autocomplete="username" required autofocus />
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password" required />
  <input type="hidden" name="auth_request" value="${authRequestJson}" />
  ${error ? html`<div class="err">${error}</div>` : raw("")}
  <button type="submit">Sign in</button>
</form></body></html>`;
}
