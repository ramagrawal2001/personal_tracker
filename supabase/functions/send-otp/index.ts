// send-otp — emails a one-time code via Resend.
//
// The client generates + stores + verifies the OTP locally (unchanged); this
// function only performs the delivery, so the Resend API key lives as a
// Supabase function secret and never ships in the app binary.
//
// Deploy (public — called before the user has a session):
//   supabase secrets set RESEND_API_KEY=re_xxx \
//     RESEND_FROM_EMAIL="Aspyric <noreply@aspyric.com>"
//   supabase functions deploy send-otp --no-verify-jwt
//
// Request  (POST): { "email": "...", "code": "123456", "purpose": "verify" | "resetPassword" }
// Response (200):  { "ok": true }
//         (4xx/5xx): { "ok": false, "error": "..." }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const CODE_RE = /^\d{4,8}$/;

// Best-effort per-email cooldown (instances are ephemeral, so this only blunts
// rapid repeats hitting the same warm instance).
const lastSent = new Map<string, number>();
const COOLDOWN_MS = 25_000;

function emailHtml(code: string, purpose: string): string {
  const purposeText = purpose === "resetPassword"
    ? "reset your password"
    : "verify your email address";
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"></head>
<body style="font-family:Inter,Arial,sans-serif;background:#0F1324;color:#E8EAFB;margin:0;padding:40px 0;">
  <div style="max-width:480px;margin:0 auto;background:#1A1F3A;border-radius:20px;border:1px solid #2D3561;padding:40px;">
    <div style="text-align:center;margin-bottom:28px;">
      <h1 style="color:#6C63FF;font-size:28px;margin:0;letter-spacing:-0.5px;">Aspyric</h1>
      <p style="color:#8B92B8;margin:8px 0 0;font-size:14px;">Your Complete Financial Dashboard</p>
    </div>
    <h2 style="color:#E8EAFB;font-size:20px;margin:0 0 12px;">Your Verification Code</h2>
    <p style="color:#8B92B8;font-size:14px;line-height:1.6;margin:0 0 28px;">
      Use the code below to ${purposeText} on Aspyric. This code expires in <strong style="color:#E8EAFB;">5 minutes</strong>.
    </p>
    <div style="background:#0F1324;border-radius:16px;border:2px solid #6C63FF;padding:24px;text-align:center;margin-bottom:28px;">
      <span style="font-size:42px;font-weight:bold;letter-spacing:14px;color:#6C63FF;font-family:monospace;">${code}</span>
    </div>
    <p style="color:#5A6180;font-size:12px;line-height:1.6;margin:0;">
      If you did not request this, you can safely ignore this email.<br>
      Never share this code with anyone.
    </p>
    <hr style="border:none;border-top:1px solid #2D3561;margin:24px 0;">
    <p style="color:#5A6180;font-size:11px;text-align:center;margin:0;">© 2026 Aspyric · support@aspyric.app</p>
  </div>
</body></html>`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "method not allowed" }, 405);

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL") ?? "Aspyric <noreply@aspyric.com>";
  if (!apiKey) return json({ ok: false, error: "email not configured" }, 503);

  let body: { email?: string; code?: string; purpose?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid json" }, 400);
  }

  const email = (body.email ?? "").trim().toLowerCase();
  const code = (body.code ?? "").trim();
  const purpose = body.purpose === "resetPassword" ? "resetPassword" : "verify";

  if (!EMAIL_RE.test(email)) return json({ ok: false, error: "invalid email" }, 400);
  if (!CODE_RE.test(code)) return json({ ok: false, error: "invalid code" }, 400);

  const now = Date.now();
  const prev = lastSent.get(email) ?? 0;
  if (now - prev < COOLDOWN_MS) {
    return json({ ok: false, error: "please wait before requesting another code" }, 429);
  }

  const subject = purpose === "resetPassword"
    ? "Aspyric — Reset your password"
    : "Aspyric — Verify your email";

  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [email],
        subject,
        html: emailHtml(code, purpose),
      }),
    });

    if (resp.status === 200 || resp.status === 201) {
      lastSent.set(email, now);
      return json({ ok: true }, 200);
    }
    const detail = await resp.text().catch(() => "");
    return json({ ok: false, error: `resend ${resp.status}: ${detail.slice(0, 200)}` }, 502);
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 502);
  }
});
