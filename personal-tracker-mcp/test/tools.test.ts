import { describe, expect, test, vi } from "vitest";
import { registerTools, type ToolDeps } from "../src/mcp/tools";
import { AuthError } from "../src/auth/supabase-auth";

type Handler = (args: any) => Promise<any>;

function harness(rest: Partial<ToolDeps["rest"]>) {
  const handlers = new Map<string, Handler>();
  const server = {
    tool: (name: string, _d: string, _s: unknown, h: Handler) => handlers.set(name, h),
  };
  const deps: ToolDeps = {
    rest: {
      list: vi.fn(), get: vi.fn(), insert: vi.fn(), patch: vi.fn(), ...rest,
    } as ToolDeps["rest"],
    identity: () => ({ email: "me@x.com", supabaseUserId: "u1", connectedAt: "2026-09-08T00:00:00.000Z" }),
  };
  registerTools(server as any, deps);
  return { handlers, deps };
}

const parse = (r: any) => JSON.parse(r.content[0].text);

describe("whoami", () => {
  test("returns the connected identity", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("whoami")!({});
    expect(parse(r)).toMatchObject({ email: "me@x.com", supabaseUserId: "u1" });
  });
});

describe("list_records", () => {
  test("lists a table and strips omitted fields", async () => {
    const list = vi.fn().mockResolvedValue([{ id: "a1", name: "HDFC", enc_ifsc: "SECRET" }]);
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "accounts" });
    expect(list).toHaveBeenCalledWith("accounts", { eq: undefined, limit: undefined });
    expect(parse(r)).toEqual([{ id: "a1", name: "HDFC" }]);
  });

  test("passes exact-match filters through", async () => {
    const list = vi.fn().mockResolvedValue([]);
    const { handlers } = harness({ list });
    await handlers.get("list_records")!({ entity: "transactions", filter: { type: "expense" }, limit: 5 });
    expect(list).toHaveBeenCalledWith("transactions", { eq: { type: "expense" }, limit: 5 });
  });

  test("accounts + with_account_balance attaches a computed calculated_balance", async () => {
    const list = vi.fn(async (t: string) => {
      if (t === "accounts") return [{ id: "A", name: "HDFC", opening_balance: 1000, calculated_balance: 999 }];
      if (t === "transactions") return [{ account_id: "A", to_account_id: null, type: "income", amount: 200, credit_card_id: null, is_external_to_account: false }];
      if (t === "credit_cards") return [];
      return [];
    });
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "accounts", with_account_balance: true });
    expect(parse(r)[0]).toMatchObject({ calculated_balance: 1200, calculated_balance_synced: 999 });
  });

  test("budgets + with_budget_spent recomputes spent_amount from transactions", async () => {
    const list = vi.fn(async (t: string) => {
      if (t === "budgets") return [{ id: "b1", category_id: "food", month_year: "2026-09", monthly_limit: 8000, spent_amount: 0 }];
      if (t === "transactions") return [
        { category_id: "food", type: "expense", amount: 1200, date: "2026-09-03T00:00:00.000Z" },
        { category_id: "food", type: "expense", amount: 800, date: "2026-08-30T00:00:00.000Z" },
      ];
      return [];
    });
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "budgets", with_budget_spent: true });
    expect(parse(r)[0]).toMatchObject({ spent_amount: 1200, spent_amount_synced: 0 });
  });

  test("AuthError becomes the reconnect message", async () => {
    const list = vi.fn().mockRejectedValue(new AuthError("SESSION_EXPIRED"));
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "loans" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/session has expired/i);
  });
});

describe("get_record", () => {
  test("returns { found: false } when missing", async () => {
    const { handlers } = harness({ get: vi.fn().mockResolvedValue(null) });
    const r = await handlers.get("get_record")!({ entity: "goals", id: "nope" });
    expect(parse(r)).toEqual({ found: false });
  });
});

describe("create_record", () => {
  test("rejects invalid data with a field-specific message", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("create_record")!({ entity: "accounts", data: { name: "X", type: "checking" } });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/Invalid account data: type/);
  });

  test("creates a row with id + timestamps and returns it stripped", async () => {
    const insert = vi.fn(async (_t: string, row: any) => ({ ...row, enc_ifsc: "SECRET" }));
    const { handlers } = harness({ insert });
    const r = await handlers.get("create_record")!({
      entity: "accounts",
      data: { name: "HDFC", type: "savingsAccount", opening_balance: 500 },
    });
    const [, row] = insert.mock.calls[0];
    expect(row.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(row).toMatchObject({ name: "HDFC", type: "savingsAccount", opening_balance: 500, is_active: true });
    expect(row.created_at).toEqual(row.updated_at);
    expect(parse(r).enc_ifsc).toBeUndefined();
  });

  test("transactions.date defaults to now when omitted; fixed fields applied", async () => {
    const insert = vi.fn(async (_t: string, row: any) => row);
    const { handlers } = harness({ insert });
    await handlers.get("create_record")!({
      entity: "transactions",
      data: { account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 100 },
    });
    const [, row] = insert.mock.calls[0];
    expect(row.date).toBeTruthy();
    expect(row.sync_status).toBe("synced");
    expect(row.splits).toEqual([]);
  });
});

describe("update_record", () => {
  test("patches only provided fields plus updated_at", async () => {
    const patch = vi.fn(async (..._a: any[]) => ({ id: "g1", name: "New Goal" }));
    const { handlers } = harness({ patch });
    await handlers.get("update_record")!({ entity: "goals", id: "g1", changes: { name: "New Goal" } });
    const [table, id, body] = patch.mock.calls[0] as any[];
    expect([table, id]).toEqual(["goals", "g1"]);
    expect(body.name).toBe("New Goal");
    expect(body.updated_at).toBeTruthy();
  });

  test("empty changes are rejected", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("update_record")!({ entity: "goals", id: "g1", changes: {} });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/No valid fields/);
  });
});

describe("delete_record", () => {
  test("soft-deletes via patch and reports the result", async () => {
    const patch = vi.fn(async (..._a: any[]) => ({ id: "l1", is_deleted: true }));
    const { handlers } = harness({ patch });
    const r = await handlers.get("delete_record")!({ entity: "loans", id: "l1" });
    const [table, id, body] = patch.mock.calls[0] as any[];
    expect([table, id]).toEqual(["loans", "l1"]);
    expect(body).toMatchObject({ is_deleted: true });
    expect(body.deleted_at).toBeTruthy();
    expect(parse(r)).toEqual({ deleted: true, id: "l1" });
  });
});

describe("add_transaction", () => {
  const accounts = [
    { id: "a-hdfc", name: "HDFC Savings" },
    { id: "a-cash", name: "Cash" },
    { id: "a-dup", name: "Wallet" },
    { id: "a-dup2", name: "Wallet" },
  ];
  const categories = [{ id: "c-food", name: "Food & Dining" }];

  function restFor() {
    return {
      list: vi.fn(async (t: string) => (t === "accounts" ? accounts : t === "categories" ? categories : [])),
      insert: vi.fn(async (_t: string, row: any) => row),
    };
  }

  test("resolves account + category by name and builds the row", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({
      type: "expense", amount: 500, account: "hdfc savings", category: "Food & Dining", merchant: "Swiggy",
    });
    const [, row] = rest.insert.mock.calls[0];
    expect(row).toMatchObject({
      account_id: "a-hdfc", category_id: "c-food", type: "expense", amount: 500,
      merchant: "Swiggy", to_account_id: null, sync_status: "synced",
    });
    expect(row.date).toBeTruthy();
    expect(parse(r).account_id).toBe("a-hdfc");
  });

  test("accepts an id directly", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    await handlers.get("add_transaction")!({ type: "income", amount: 1000, account: "a-cash" });
    expect(rest.insert.mock.calls[0][1].account_id).toBe("a-cash");
  });

  test("unknown account name lists the candidates", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({ type: "expense", amount: 10, account: "SBI" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/No account named "SBI"/);
    expect(r.content[0].text).toMatch(/HDFC Savings/);
  });

  test("ambiguous name is rejected", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({ type: "expense", amount: 10, account: "Wallet" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/Multiple accounts named "Wallet"/);
  });

  test("transfer requires to_account and sets to_account_id", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const missing = await handlers.get("add_transaction")!({ type: "transfer", amount: 100, account: "HDFC Savings" });
    expect(missing.isError).toBe(true);
    expect(missing.content[0].text).toMatch(/needs `to_account`/);

    await handlers.get("add_transaction")!({ type: "transfer", amount: 100, account: "HDFC Savings", to_account: "Cash" });
    expect(rest.insert.mock.calls[0][1]).toMatchObject({ account_id: "a-hdfc", to_account_id: "a-cash" });
  });
});
