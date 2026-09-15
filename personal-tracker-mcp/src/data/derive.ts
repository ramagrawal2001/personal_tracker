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
