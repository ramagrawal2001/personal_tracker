import { describe, expect, test } from "vitest";
import {
  ACCOUNT_TYPES, TRANSACTION_TYPES, PAYMENT_FREQUENCIES, INVESTMENT_TYPES,
  CARD_TYPES, CARD_NETWORKS, CARD_COLOR_PRESETS, CATEGORY_TYPES,
  ENTITIES, ENTITY_NAMES,
} from "../src/data/entities";

describe("enum parity with the Flutter app", () => {
  test("values match app_constants.dart / models.dart exactly", () => {
    expect(ACCOUNT_TYPES).toEqual([
      "bankAccount", "cash", "savingsAccount", "currentAccount", "wallet",
      "fd", "rd", "investmentAccount", "otherAsset",
    ]);
    expect(TRANSACTION_TYPES).toEqual([
      "income", "expense", "transfer", "creditCardPayment", "loanPayment",
      "investment", "refund", "adjustment",
    ]);
    expect(PAYMENT_FREQUENCIES).toEqual(["daily", "weekly", "monthly", "quarterly", "yearly"]);
    expect(INVESTMENT_TYPES).toEqual([
      "mutualFundSip", "stocks", "fixedDeposit", "recurringDeposit", "gold",
      "ppf", "epf", "crypto", "other",
    ]);
    expect(CARD_TYPES).toEqual(["credit", "debit", "prepaid", "store", "forex"]);
    expect(CARD_NETWORKS).toEqual(["visa", "mastercard", "rupay", "amex", "diners", "other"]);
    expect(CARD_COLOR_PRESETS).toEqual([
      "midnight", "gold", "rose", "emerald", "slate", "violet", "crimson", "ocean",
    ]);
    expect(CATEGORY_TYPES).toEqual(["income", "expense"]);
  });
});

describe("entity registry", () => {
  test("exactly the 13 v1 entities, notes excluded", () => {
    expect([...ENTITY_NAMES].sort()).toEqual([
      "accounts", "budgets", "categories", "companies", "credit_cards",
      "goals", "investments", "loans", "people", "recurring_payments",
      "split_expenses", "split_participants", "transactions",
    ]);
  });

  test("every entity has table, schemas, omitFields", () => {
    for (const name of ENTITY_NAMES) {
      const def = ENTITIES[name];
      expect(typeof def.table).toBe("string");
      expect(def.createSchema).toBeDefined();
      expect(def.updateSchema).toBeDefined();
      expect(Array.isArray(def.omitFields)).toBe(true);
    }
  });

  test("accounts: valid create parses, bad type rejected, derived flag set", () => {
    const good = ENTITIES.accounts.createSchema.safeParse({ name: "HDFC", type: "savingsAccount" });
    expect(good.success).toBe(true);
    const bad = ENTITIES.accounts.createSchema.safeParse({ name: "X", type: "checking" });
    expect(bad.success).toBe(false);
    expect(ENTITIES.accounts.derived).toBe("accountBalance");
    expect(ENTITIES.accounts.omitFields).toContain("enc_account_number");
  });

  test("transactions: account_id must be a uuid, fixed sync_status present", () => {
    const bad = ENTITIES.transactions.createSchema.safeParse({
      account_id: "not-a-uuid", type: "expense", amount: 10,
    });
    expect(bad.success).toBe(false);
    const good = ENTITIES.transactions.createSchema.safeParse({
      account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 10,
    });
    expect(good.success).toBe(true);
    expect(ENTITIES.transactions.fixed).toMatchObject({ sync_status: "synced" });
  });

  test("transactions: is_cash_spend defaults to false", () => {
    const r = ENTITIES.transactions.createSchema.parse({
      account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 10,
    });
    expect(r.is_cash_spend).toBe(false);
  });

  test("people: name required", () => {
    expect(ENTITIES.people.createSchema.safeParse({}).success).toBe(false);
    expect(ENTITIES.people.createSchema.safeParse({ name: "Rahul" }).success).toBe(true);
  });

  test("split_expenses: mode enum, defaults to equal", () => {
    const base = { title: "Panipuri", total_amount: 100, transaction_id: "tx1" };
    expect(ENTITIES.split_expenses.createSchema.parse(base).mode).toBe("equal");
    expect(ENTITIES.split_expenses.createSchema.safeParse({ ...base, mode: "bogus" }).success).toBe(false);
    expect(ENTITIES.split_expenses.createSchema.safeParse({ ...base, total_amount: -5 }).success).toBe(false);
  });

  test("split_participants: share_amount must be positive", () => {
    const base = { split_expense_id: "s1", person_id: "p1" };
    expect(ENTITIES.split_participants.createSchema.safeParse({ ...base, share_amount: 50 }).success).toBe(true);
    expect(ENTITIES.split_participants.createSchema.safeParse({ ...base, share_amount: 0 }).success).toBe(false);
  });

  test("credit_cards: applies defaults", () => {
    const r = ENTITIES.credit_cards.createSchema.parse({ name: "Regalia" });
    expect(r).toMatchObject({ card_type: "credit", network: "visa", due_day: 15, statement_day: 1 });
  });

  test("credit_cards: last_payment_date/last_payment_amount are accepted (real columns, were missing)", () => {
    const r = ENTITIES.credit_cards.createSchema.safeParse({
      name: "Regalia", last_payment_date: "2026-09-01T00:00:00.000Z", last_payment_amount: 5000,
    });
    expect(r.success).toBe(true);
  });

  test("accounts: sort_order is accepted (real column, was missing)", () => {
    const r = ENTITIES.accounts.createSchema.safeParse({ name: "HDFC", type: "savingsAccount", sort_order: 2 });
    expect(r.success).toBe(true);
  });

  test("transactions: splits (the per-category breakdown column) is accepted (real column, was missing)", () => {
    const base = { account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 100 };
    const withSplits = ENTITIES.transactions.createSchema.safeParse({
      ...base, splits: [{ categoryId: "cat_food", amount: 60 }, { categoryId: "cat_transport", amount: 40, note: "cab" }],
    });
    expect(withSplits.success).toBe(true);
    // A caller who never mentions splits still gets the column's real default.
    expect(ENTITIES.transactions.createSchema.parse(base).splits).toEqual([]);
  });

  test("budgets: month_year must be YYYY-MM", () => {
    expect(ENTITIES.budgets.createSchema.safeParse({ category_id: "c1", month_year: "Sept" }).success).toBe(false);
    expect(ENTITIES.budgets.createSchema.safeParse({ category_id: "c1", month_year: "2026-09" }).success).toBe(true);
  });

  test("updateSchema is partial (empty object parses)", () => {
    expect(ENTITIES.goals.updateSchema.safeParse({}).success).toBe(true);
  });
});
