import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function errMsg(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // The Flutter client (supabase_flutter functions.invoke) attaches the
    // signed-in user's JWT as the Authorization header. Forward it so the
    // upserts run as that user and Row-Level Security + the `user_id`
    // (default auth.uid()) column keep each user's data isolated.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ ok: false, error: "Missing Authorization header" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ ok: false, error: "Invalid or expired session" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const accounts = Array.isArray(body.accounts) ? body.accounts : [];
    const transactions = Array.isArray(body.transactions)
      ? body.transactions
      : [];

    if (accounts.length === 0 && transactions.length === 0) {
      // A payload that syncs nothing is a client bug, not a success — return
      // 400 so the offline queue does NOT mark its items as synced.
      return json(
        { ok: false, error: "No accounts or transactions in payload" },
        400,
      );
    }

    if (accounts.length > 0) {
      const { error } = await supabase
        .from("accounts")
        .upsert(accounts, { onConflict: "id" });
      if (error) throw error;
    }

    const syncedIds: string[] = [];
    if (transactions.length > 0) {
      const { data, error } = await supabase
        .from("transactions")
        .upsert(transactions, { onConflict: "id" })
        .select("id");
      if (error) throw error;
      for (const row of data ?? []) syncedIds.push(row.id as string);
    }

    return json(
      {
        ok: true,
        synced_accounts: accounts.length,
        synced_transactions: syncedIds.length,
        synced_ids: syncedIds,
      },
      200,
    );
  } catch (error) {
    return json({ ok: false, error: errMsg(error) }, 400);
  }
});
