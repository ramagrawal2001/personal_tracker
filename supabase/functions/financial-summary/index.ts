import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseAnonKey);

    // Fetch accounts
    const { data: accounts, error: accError } = await supabase.from("accounts").select("*");
    if (accError) throw accError;

    // Fetch transactions
    const { data: transactions, error: txError } = await supabase.from("transactions").select("*");
    if (txError) throw txError;

    let totalLiquid = 0;
    for (const acc of accounts ?? []) {
      totalLiquid += acc.calculated_balance ?? acc.opening_balance ?? 0;
    }

    let monthlyIncome = 0;
    let monthlyExpenses = 0;
    for (const tx of transactions ?? []) {
      if (tx.type === "income" || tx.type === "refund") {
        monthlyIncome += tx.amount;
      } else if (tx.type === "expense") {
        monthlyExpenses += tx.amount;
      }
    }

    const summary = {
      timestamp: new Date().toISOString(),
      total_liquid_balance: totalLiquid,
      monthly_income: monthlyIncome,
      monthly_expenses: monthlyExpenses,
      net_savings: monthlyIncome - monthlyExpenses,
      safe_to_spend: Math.max(0, totalLiquid - 50000), // Buffer calculation
    };

    return new Response(JSON.stringify(summary), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
