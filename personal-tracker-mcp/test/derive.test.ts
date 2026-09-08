import { describe, expect, test } from "vitest";
import {
  computeAccountBalance, computeBudgetSpent, type BalanceTxn, type SpentTxn,
} from "../src/data/derive";

const acc = { id: "A", opening_balance: 1000 };
const tx = (p: Partial<BalanceTxn>): BalanceTxn => ({
  account_id: "A", to_account_id: null, type: "expense", amount: 0,
  credit_card_id: null, is_external_to_account: false, ...p,
});

describe("computeAccountBalance — port of FinanceState.accountsWithCalculatedBalances", () => {
  test("opening balance only", () => {
    expect(computeAccountBalance(acc, [], new Set())).toBe(1000);
  });
  test("income and refund add", () => {
    expect(computeAccountBalance(acc, [tx({ type: "income", amount: 500 }), tx({ type: "refund", amount: 100 })], new Set())).toBe(1600);
  });
  test("expense / transfer / cc payment / loan payment / investment / adjustment subtract", () => {
    const txns = ["expense", "transfer", "creditCardPayment", "loanPayment", "investment", "adjustment"]
      .map((t) => tx({ type: t, amount: 100 }));
    expect(computeAccountBalance(acc, txns, new Set())).toBe(1000 - 600);
  });
  test("incoming transfer (to_account_id) adds regardless of type", () => {
    expect(computeAccountBalance(acc, [tx({ account_id: "B", to_account_id: "A", type: "transfer", amount: 250 })], new Set())).toBe(1250);
  });
  test("is_external_to_account rows are skipped on the account_id leg", () => {
    expect(computeAccountBalance(acc, [tx({ type: "expense", amount: 300, is_external_to_account: true })], new Set())).toBe(1000);
  });
  test("credit-card charge rows are skipped (credit card id + expense/refund)", () => {
    const credit = new Set(["card1"]);
    expect(computeAccountBalance(acc, [
      tx({ type: "expense", amount: 400, credit_card_id: "card1" }),
      tx({ type: "refund", amount: 50, credit_card_id: "card1" }),
    ], credit)).toBe(1000);
  });
  test("a charge on a NON-credit card still counts", () => {
    expect(computeAccountBalance(acc, [tx({ type: "expense", amount: 400, credit_card_id: "debit9" })], new Set(["card1"]))).toBe(600);
  });
  test("rows for other accounts are ignored", () => {
    expect(computeAccountBalance(acc, [tx({ account_id: "Z", type: "expense", amount: 999 })], new Set())).toBe(1000);
  });
});

describe("computeBudgetSpent", () => {
  const b = { category_id: "food", month_year: "2026-09" };
  const st = (p: Partial<SpentTxn>): SpentTxn => ({
    category_id: "food", type: "expense", amount: 0, date: "2026-09-15T10:00:00.000Z", ...p,
  });
  test("sums matching expense rows in the month", () => {
    expect(computeBudgetSpent(b, [st({ amount: 100 }), st({ amount: 250 })])).toBe(350);
  });
  test("ignores other categories, other months, and non-expense types", () => {
    expect(computeBudgetSpent(b, [
      st({ amount: 100, category_id: "rent" }),
      st({ amount: 100, date: "2026-08-31T23:59:59.000Z" }),
      st({ amount: 100, type: "income" }),
      st({ amount: 40 }),
    ])).toBe(40);
  });
  test("null category never matches", () => {
    expect(computeBudgetSpent(b, [st({ amount: 100, category_id: null })])).toBe(0);
  });
});
