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

describe("add_split_expense", () => {
  const accounts = [{ id: "a-hdfc", name: "HDFC Savings" }];
  const cards = [{ id: "card-1", name: "Regalia" }];
  const categories = [{ id: "c-food", name: "Food & Dining" }];
  const people = [{ id: "p-rahul", name: "Rahul" }];

  function restFor() {
    return {
      list: vi.fn(async (t: string) =>
        t === "accounts" ? accounts : t === "credit_cards" ? cards : t === "categories" ? categories : t === "people" ? people : [],
      ),
      insert: vi.fn(async (_t: string, row: any) => row),
      get: vi.fn(),
    };
  }

  test("logs the full amount as the real expense and creates the split + participant rows", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_split_expense")!({
      title: "Panipuri", total_amount: 100, account: "HDFC Savings",
      mode: "equal", participants: [{ person: "Rahul" }],
    });
    expect(r.isError).toBeFalsy();

    const [txCall, splitCall, participantCall] = rest.insert.mock.calls;
    expect(txCall[0]).toBe("transactions");
    expect(txCall[1]).toMatchObject({ account_id: "a-hdfc", type: "expense", amount: 100, merchant: "Panipuri" });

    expect(splitCall[0]).toBe("split_expenses");
    expect(splitCall[1]).toMatchObject({ title: "Panipuri", total_amount: 100, transaction_id: txCall[1].id, mode: "equal" });

    expect(participantCall[0]).toBe("split_participants");
    expect(participantCall[1]).toMatchObject({ person_id: "p-rahul", split_expense_id: splitCall[1].id, share_amount: 50 });
  });

  test("auto-creates a person that doesn't exist yet", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    await handlers.get("add_split_expense")!({
      title: "Dinner", total_amount: 200, account: "HDFC Savings",
      mode: "equal", participants: [{ person: "Priya" }],
    });
    const personInsert = rest.insert.mock.calls.find((c: any) => c[0] === "people")!;
    expect(personInsert[1]).toMatchObject({ name: "Priya" });
  });

  test("charges a credit card instead of debiting the account", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    await handlers.get("add_split_expense")!({
      title: "Dinner", total_amount: 1000, account: "HDFC Savings", credit_card: "Regalia",
      mode: "equal", participants: [{ person: "Rahul" }],
    });
    const txInsert = rest.insert.mock.calls.find((c: any) => c[0] === "transactions")!;
    expect(txInsert[1]).toMatchObject({ credit_card_id: "card-1" });
  });

  test("ratio mode requires payer_value", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_split_expense")!({
      title: "Trip", total_amount: 300, account: "HDFC Savings",
      mode: "ratio", participants: [{ person: "Rahul", value: 1 }],
    });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/payer_value.*required/);
  });

  test("custom shares exceeding the total are rejected", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_split_expense")!({
      title: "Trip", total_amount: 100, account: "HDFC Savings",
      mode: "custom", participants: [{ person: "Rahul", value: 150 }],
    });
    expect(r.isError).toBe(true);
  });

  test("per-participant category/note are resolved and stored on the participant row", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    await handlers.get("add_split_expense")!({
      title: "Groceries", total_amount: 500, account: "HDFC Savings",
      mode: "custom", participants: [{ person: "Rahul", value: 250, category: "Food & Dining", note: "his half" }],
    });
    const participantCall = rest.insert.mock.calls.find((c: any) => c[0] === "split_participants")!;
    expect(participantCall[1]).toMatchObject({
      person_id: "p-rahul", share_amount: 250, category_id: "c-food", note: "his half", settled_amount: 0,
    });
  });
});

describe("split_participants reconciliation guard", () => {
  test("create_record rejects a share that would push the split over its total", async () => {
    const get = vi.fn(async () => ({ id: "s1", title: "Panipuri", total_amount: 100 }));
    const list = vi.fn(async () => [{ id: "sp-existing", share_amount: 60 }]);
    const { handlers } = harness({ get, list });
    const r = await handlers.get("create_record")!({
      entity: "split_participants",
      data: { split_expense_id: "s1", person_id: "p1", share_amount: 50 },
    });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/doesn't reconcile/);
  });

  test("create_record allows a share that fits within the total", async () => {
    const get = vi.fn(async () => ({ id: "s1", title: "Panipuri", total_amount: 100 }));
    const list = vi.fn(async () => [{ id: "sp-existing", share_amount: 30 }]);
    const insert = vi.fn(async (_t: string, row: any) => row);
    const { handlers } = harness({ get, list, insert });
    const r = await handlers.get("create_record")!({
      entity: "split_participants",
      data: { split_expense_id: "s1", person_id: "p1", share_amount: 50 },
    });
    expect(r.isError).toBeFalsy();
    expect(insert).toHaveBeenCalled();
  });

  test("update_record re-checks reconciliation when share_amount changes", async () => {
    const get = vi.fn(async (t: string) =>
      t === "split_participants"
        ? { id: "sp1", split_expense_id: "s1", share_amount: 30 }
        : { id: "s1", title: "Panipuri", total_amount: 100 },
    );
    const list = vi.fn(async () => [{ id: "sp-other", share_amount: 60 }]);
    const { handlers } = harness({ get, list });
    const r = await handlers.get("update_record")!({
      entity: "split_participants", id: "sp1", changes: { share_amount: 50 },
    });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/doesn't reconcile/);
  });
});

describe("settle_person", () => {
  function restFor() {
    const people = [{ id: "p1", name: "Rahul" }];
    const splits = [
      { id: "s-old", date: "2026-01-01T00:00:00.000Z" },
      { id: "s-new", date: "2026-06-01T00:00:00.000Z" },
    ];
    const participants = [
      { id: "sp-old", person_id: "p1", split_expense_id: "s-old", share_amount: 40, settled_amount: 0 },
      { id: "sp-new", person_id: "p1", split_expense_id: "s-new", share_amount: 40, settled_amount: 0 },
    ];
    return {
      people, splits, participants,
      list: vi.fn(async (t: string) =>
        t === "people" ? people : t === "split_expenses" ? splits : t === "split_participants" ? participants : [],
      ),
      insert: vi.fn(async (_t: string, row: any) => row),
      patch: vi.fn(async (_t: string, id: string, changes: any) => ({ id, ...changes })),
    };
  }

  test("without account: only settled_amount updates, no transaction recorded", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("settle_person")!({ person: "Rahul", amount: 40 });
    expect(r.isError).toBeFalsy();
    expect(rest.insert).not.toHaveBeenCalled();
    expect(rest.patch).toHaveBeenCalledWith(
      "split_participants", "sp-old",
      expect.objectContaining({ settled_amount: 40, settled_transaction_id: null }),
    );
  });

  test("applies oldest-first across multiple splits and caps at what's owed", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("settle_person")!({ person: "Rahul", amount: 50 });
    expect(r.isError).toBeFalsy();
    const patchCalls = rest.patch.mock.calls.map((c: any) => [c[1], c[2].settled_amount]);
    expect(patchCalls).toEqual(
      expect.arrayContaining([
        ["sp-old", 40],
        ["sp-new", 10],
      ]),
    );
    const parsed = parse(r);
    expect(parsed.applied).toBe(50);
  });

  test("records a real credit transaction when an account is given", async () => {
    const rest: any = restFor();
    rest.list = vi.fn(async (t: string) =>
      t === "people" ? rest.people
        : t === "split_expenses" ? rest.splits
        : t === "split_participants" ? rest.participants
        : t === "accounts" ? [{ id: "a-hdfc", name: "HDFC Savings" }]
        : [],
    );
    const { handlers } = harness(rest);
    await handlers.get("settle_person")!({ person: "Rahul", amount: 40, account: "HDFC Savings" });
    const txCall = rest.insert.mock.calls.find((c: any) => c[0] === "transactions")!;
    expect(txCall[1]).toMatchObject({ type: "refund", amount: 40, account_id: "a-hdfc", is_settlement: true });
  });

  test("person with nothing unsettled is rejected", async () => {
    const rest = restFor();
    rest.participants.forEach((p: any) => (p.settled_amount = p.share_amount));
    const { handlers } = harness(rest);
    const r = await handlers.get("settle_person")!({ person: "Rahul", amount: 10 });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/no unsettled split shares/);
  });

  test("unknown person is rejected", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("settle_person")!({ person: "Nobody", amount: 10 });
    expect(r.isError).toBe(true);
  });
});

describe("add_payable / settle_payable", () => {
  test("add_payable resolves an existing person and inserts the row", async () => {
    const list = vi.fn(async (t: string) => (t === "people" ? [{ id: "p1", name: "Aniket" }] : []));
    const insert = vi.fn(async (_t: string, row: any) => row);
    const { handlers } = harness({ list, insert });
    const r = await handlers.get("add_payable")!({ person: "Aniket", amount: 300, description: "Cab" });
    expect(r.isError).toBeFalsy();
    const [table, row] = insert.mock.calls[0];
    expect(table).toBe("payables");
    expect(row).toMatchObject({ person_id: "p1", amount: 300, description: "Cab", settled_amount: 0 });
  });

  test("add_payable auto-creates an unknown person", async () => {
    const list = vi.fn(async (t: string) => (t === "people" ? [] : []));
    const insert = vi.fn(async (_t: string, row: any) => row);
    const { handlers } = harness({ list, insert });
    await handlers.get("add_payable")!({ person: "Priya", amount: 100, description: "Loan" });
    const personInsert = insert.mock.calls.find((c: any) => c[0] === "people")!;
    expect(personInsert[1]).toMatchObject({ name: "Priya" });
  });

  test("settle_payable applies oldest-first and records an expense when an account is given", async () => {
    const people = [{ id: "p1", name: "Aniket" }];
    const payables = [
      { id: "pay-old", person_id: "p1", amount: 100, settled_amount: 0, date: "2026-01-01T00:00:00.000Z" },
      { id: "pay-new", person_id: "p1", amount: 100, settled_amount: 0, date: "2026-06-01T00:00:00.000Z" },
    ];
    const accounts = [{ id: "a-hdfc", name: "HDFC Savings" }];
    const list = vi.fn(async (t: string) =>
      t === "people" ? people : t === "payables" ? payables : t === "accounts" ? accounts : [],
    );
    const insert = vi.fn(async (_t: string, row: any) => row);
    const patch = vi.fn(async (_t: string, id: string, changes: any) => ({ id, ...changes }));
    const { handlers } = harness({ list, insert, patch });

    const r = await handlers.get("settle_payable")!({ person: "Aniket", amount: 150, account: "HDFC Savings" });
    expect(r.isError).toBeFalsy();
    const txCall = insert.mock.calls.find((c: any) => c[0] === "transactions")!;
    expect(txCall[1]).toMatchObject({ type: "expense", amount: 150, account_id: "a-hdfc", is_settlement: true });
    const patchCalls = patch.mock.calls.map((c: any) => [c[1], c[2].settled_amount]);
    expect(patchCalls).toEqual(expect.arrayContaining([["pay-old", 100], ["pay-new", 50]]));
  });

  test("settle_payable with nothing unsettled is rejected", async () => {
    const people = [{ id: "p1", name: "Aniket" }];
    const list = vi.fn(async (t: string) => (t === "people" ? people : t === "payables" ? [] : []));
    const { handlers } = harness({ list });
    const r = await handlers.get("settle_payable")!({ person: "Aniket", amount: 10 });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/no unsettled payables/);
  });
});

describe("person_balance / list_balances", () => {
  test("person_balance nets unsettled receivables against unsettled payables", async () => {
    const people = [{ id: "p1", name: "Rahul" }];
    const participants = [{ person_id: "p1", share_amount: 100, settled_amount: 40 }];
    const payables = [{ person_id: "p1", amount: 20, settled_amount: 0 }];
    const list = vi.fn(async (t: string) =>
      t === "people" ? people : t === "split_participants" ? participants : t === "payables" ? payables : [],
    );
    const { handlers } = harness({ list });
    const r = await handlers.get("person_balance")!({ person: "Rahul" });
    // owed to me: 100-40=60; I owe: 20-0=20; net = 40
    expect(parse(r)).toMatchObject({ person_id: "p1", name: "Rahul", balance: 40 });
  });

  test("list_balances only returns people with a non-zero net", async () => {
    const people = [{ id: "p1", name: "Rahul" }, { id: "p2", name: "Settled Sam" }];
    const participants = [
      { person_id: "p1", share_amount: 100, settled_amount: 0 },
      { person_id: "p2", share_amount: 50, settled_amount: 50 },
    ];
    const list = vi.fn(async (t: string) =>
      t === "people" ? people : t === "split_participants" ? participants : t === "payables" ? [] : [],
    );
    const { handlers } = harness({ list });
    const r = await handlers.get("list_balances")!({});
    expect(parse(r)).toEqual([{ person_id: "p1", name: "Rahul", balance: 100 }]);
  });
});
