export interface Session {
  supabaseUserId: string;
  email: string;
  accessToken: string;
  refreshToken: string;
  /** epoch seconds */
  expiresAt: number;
}

export interface GoTrueConfig {
  url: string;
  anonKey: string;
}

export class AuthError extends Error {}

interface GoTrueToken {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  user: { id: string; email: string };
  error_description?: string;
  error?: string;
  msg?: string;
}

function toSession(t: GoTrueToken): Session {
  return {
    supabaseUserId: t.user.id,
    email: t.user.email,
    accessToken: t.access_token,
    refreshToken: t.refresh_token,
    expiresAt: t.expires_at,
  };
}

async function tokenRequest(
  cfg: GoTrueConfig,
  grant: "password" | "refresh_token",
  payload: Record<string, string>,
): Promise<GoTrueToken> {
  const res = await fetch(`${cfg.url}/auth/v1/token?grant_type=${grant}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: cfg.anonKey },
    body: JSON.stringify(payload),
  });
  const body = (await res.json().catch(() => ({}))) as GoTrueToken;
  if (!res.ok || !body.access_token) {
    const msg = body.error_description || body.msg || body.error || `Auth failed (${res.status})`;
    throw new AuthError(grant === "refresh_token" ? "SESSION_EXPIRED" : msg);
  }
  return body;
}

export async function signInWithPassword(
  cfg: GoTrueConfig,
  email: string,
  password: string,
): Promise<Session> {
  return toSession(await tokenRequest(cfg, "password", { email, password }));
}

export async function refreshSession(cfg: GoTrueConfig, refreshToken: string): Promise<Session> {
  return toSession(await tokenRequest(cfg, "refresh_token", { refresh_token: refreshToken }));
}
