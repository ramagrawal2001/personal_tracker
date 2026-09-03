import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

// Keep in sync with FinanceState.emergencyBuffer's default in
// lib/core/database/finance_repository.dart.
const DEFAULT_EMERGENCY_BUFFER = 20000;

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
    // Forward the caller's JWT so every query is scoped to that user by RLS.
    // Without this the function ran as the anon role and (absent RLS) would
    // have returned every user's rows to any caller.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }

    let buffer = DEFAULT_EMERGENCY_BUFFER;
    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      if (typeof body.emergency_buffer === "number" && body.emergency_buffer >= 0) {
        buffer = body.emergency_buffer;
      }
    }

    const { data: accounts, error: accError } = await supabase
      .from("accounts")
      .select("type, is_active, opening_balance, calculated_balance");
    if (accError) throw accError;

    const { data: transactions, error: txError } = await supabase
      .from("transactions")
      .select("type, amount, date");
    if (txError) throw txError;

    // Liquid = active cash-like accounts only, mirroring
    // FinanceState.totalLiquidBalance.
    const LIQUID_TYPES = new Set([
      "bankAccount",
      "savingsAccount",
      "currentAccount",
      "cash",
      "wallet",
    ]);
    let totalLiquid = 0;
    for (const acc of accounts ?? []) {
      if (acc.is_active === false) continue;
      if (!LIQUID_TYPES.has(acc.type)) continue;
      totalLiquid += acc.calculated_balance ?? acc.opening_balance ?? 0;
    }

    // Current-month income / expenses, mirroring FinanceState.monthlyIncome /
    // monthlyExpenses.
    const now = new Date();
    const y = now.getUTCFullYear();
    const m = now.getUTCMonth();
    let monthlyIncome = 0;
    let monthlyExpenses = 0;
    for (const tx of transactions ?? []) {
      const d = new Date(tx.date);
      if (d.getUTCFullYear() !== y || d.getUTCMonth() !== m) continue;
      if (tx.type === "income" || tx.type === "refund") {
        monthlyIncome += tx.amount;
      } else if (tx.type === "expense") {
        monthlyExpenses += tx.amount;
      }
    }

    // NOTE: recurring-payment obligations are not mirrored to the cloud, so
    // this cannot subtract upcomingPaymentsTotal the way the in-app
    // FinanceState.safeToSpend does — it is liquid minus the buffer only.
    const summary = {
      timestamp: new Date().toISOString(),
      total_liquid_balance: totalLiquid,
      monthly_income: monthlyIncome,
      monthly_expenses: monthlyExpenses,
      net_savings: monthlyIncome - monthlyExpenses,
      emergency_buffer: buffer,
      safe_to_spend: Math.max(0, totalLiquid - buffer),
    };

    return json(summary, 200);
  } catch (error) {
    return json({ error: errMsg(error) }, 400);
  }
});
