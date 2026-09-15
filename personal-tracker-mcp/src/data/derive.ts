export interface BalanceTxn {
  account_id: string;
  to_account_id: string | null;
  type: string;
  amount: number;
  credit_card_id: string | null;
  is_external_to_account: boolean;
  is_cash_spend?: boolean;
}

const DEBIT_TYPES = new Set([
  "expense", "transfer", "creditCardPayment", "loanPayment", "investment", "adjustment",
]);

/**
 * Port of FinanceState.accountsWithCalculatedBalances
 * (lib/core/database/finance_repository.dart).
 *
 * balance = opening_balance
 *   + income/refund posted to this account
 *   - expense/transfer/creditCardPayment/loanPayment/investment/adjustment posted to this account
 *   + amount for every transaction whose to_account_id is this account
 * Skips rows where is_external_to_account or is_cash_spend is true, and "card
 * charge" rows whose credit_card_id belongs to a credit card and whose type
 * is expense or refund.
 */
export function computeAccountBalance(
  account: { id: string; opening_balance: number },
  txns: readonly BalanceTxn[],
  creditCardIds: ReadonlySet<string>,
): number {
  let calc = account.opening_balance;
  for (const t of txns) {
    if (t.account_id === account.id) {
      const isCardCharge =
        t.credit_card_id != null &&
        creditCardIds.has(t.credit_card_id) &&
        (t.type === "expense" || t.type === "refund");
      if (!isCardCharge && !t.is_external_to_account && !t.is_cash_spend) {
        if (t.type === "income" || t.type === "refund") calc += t.amount;
        else if (DEBIT_TYPES.has(t.type)) calc -= t.amount;
      }
    }
    if (t.to_account_id === account.id) calc += t.amount;
  }
  return calc;
}

export type SplitMode = "equal" | "custom" | "ratio" | "percentage";

/**
 * Port of resolveSplitShares
 * (lib/features/splits/presentation/split_expense_modal.dart).
 *
 * Resolves each participant's owed share given `mode` and their raw input
 * (interpretation depends on mode) plus the payer's own raw input (only
 * meaningful for ratio/percentage). Returns null when the inputs don't
 * resolve to something valid. The payer's own share is never part of the
 * returned record — callers compute it as `totalAmount - sum(shares)`.
 */
export function resolveSplitShares(args: {
  mode: SplitMode;
  totalAmount: number;
  participantIds: readonly string[];
  participantInputs: Readonly<Record<string, number>>;
  payerInput?: number;
}): Record<string, number> | null {
  const { mode, totalAmount, participantIds, participantInputs } = args;
  const payerInput = args.payerInput ?? 1;
  if (participantIds.length === 0 || totalAmount <= 0) return null;
  const round2 = (n: number) => Math.round(n * 100) / 100;
  const sumInputs = () => participantIds.reduce((s, id) => s + (participantInputs[id] ?? 0), 0);

  switch (mode) {
    case "equal": {
      const each = round2(totalAmount / (participantIds.length + 1));
      return Object.fromEntries(participantIds.map((id) => [id, each]));
    }
    case "custom": {
      const sum = sumInputs();
      if (sum <= 0 || sum > totalAmount + 0.01) return null;
      return Object.fromEntries(participantIds.map((id) => [id, participantInputs[id] ?? 0]));
    }
    case "ratio": {
      const ratioSum = payerInput + sumInputs();
      if (ratioSum <= 0) return null;
      return Object.fromEntries(
        participantIds.map((id) => [id, round2((totalAmount * (participantInputs[id] ?? 0)) / ratioSum)]),
      );
    }
    case "percentage": {
      const pctSum = payerInput + sumInputs();
      if (Math.abs(pctSum - 100) > 0.5) return null;
      return Object.fromEntries(
        participantIds.map((id) => [id, round2((totalAmount * (participantInputs[id] ?? 0)) / 100)]),
      );
    }
  }
}

export interface SpentTxn {
  category_id: string | null;
  type: string;
  amount: number;
  date: string;
}

/**
 * Recomputes a budget's spent_amount from live transactions — the same rule the
 * app's Budgets screen uses: non-deleted `expense` rows in the budget's category
 * whose date falls inside `month_year` ("YYYY-MM"). Callers pass only
 * non-deleted rows (the PostgREST list already filters is_deleted).
 */
export function computeBudgetSpent(
  budget: { category_id: string; month_year: string },
  txns: readonly SpentTxn[],
): number {
  let spent = 0;
  for (const t of txns) {
    if (
      t.type === "expense" &&
      t.category_id != null &&
      t.category_id === budget.category_id &&
      typeof t.date === "string" &&
      t.date.startsWith(budget.month_year)
    ) {
      spent += t.amount;
    }
  }
  return spent;
}
