import { z } from "zod";

/**
 * Enum wire values = Dart enum `.name` strings. Keep in sync with:
 *   AccountType / TransactionType / PaymentFrequency / InvestmentType
 *     -> lib/core/constants/app_constants.dart
 *   CardType / CardNetwork / CardColorPreset -> lib/domain/models/models.dart
 *   category `type` -> CategoryModel ('income' | 'expense')
 */
export const ACCOUNT_TYPES = [
  "bankAccount", "cash", "savingsAccount", "currentAccount", "wallet",
  "fd", "rd", "investmentAccount", "otherAsset",
] as const;
export const TRANSACTION_TYPES = [
  "income", "expense", "transfer", "creditCardPayment", "loanPayment",
  "investment", "refund", "adjustment",
] as const;
export const PAYMENT_FREQUENCIES = ["daily", "weekly", "monthly", "quarterly", "yearly"] as const;
export const INVESTMENT_TYPES = [
  "mutualFundSip", "stocks", "fixedDeposit", "recurringDeposit", "gold",
  "ppf", "epf", "crypto", "other",
] as const;
export const CARD_TYPES = ["credit", "debit", "prepaid", "store", "forex"] as const;
export const CARD_NETWORKS = ["visa", "mastercard", "rupay", "amex", "diners", "other"] as const;
export const CARD_COLOR_PRESETS = [
  "midnight", "gold", "rose", "emerald", "slate", "violet", "crimson", "ocean",
] as const;
export const CATEGORY_TYPES = ["income", "expense"] as const;

const isoDate = z.string().datetime({ offset: true });
const optStr = z.string().trim().min(1).optional();

export interface EntityDef {
  table: string;
  displayName: string;
  uuidId: boolean;
  createSchema: z.ZodType;
  updateSchema: z.ZodType;
  omitFields: readonly string[];
  fixed?: Record<string, unknown>;
  derived?: "accountBalance";
}

const accountCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(ACCOUNT_TYPES),
  bank: optStr,
  account_number_last4: z.string().regex(/^\d{4}$/).optional(),
  opening_balance: z.number().default(0),
  currency: z.string().trim().min(1).default("INR"),
  is_active: z.boolean().default(true),
  // Display position in the app's Accounts list — lower sorts first.
  sort_order: z.number().int().optional(),
}).strict();

// Postgres `uuid` columns accept any RFC-4122-shaped value (no version/variant
// check), and crypto.randomUUID() always satisfies it — so use the lenient
// GUID format, not zod's strict versioned .uuid().
const guid = z.guid();

// Real jsonb column (0002_sync_all_entities.sql) — an older per-category
// breakdown feature, unrelated to the newer split_expenses/split_participants
// tables. Keys are camelCase because that's the literal shape
// TransactionSplit.toMap() in the Flutter app serializes into this column.
const transactionSplitItem = z.object({
  categoryId: z.string().trim().min(1),
  amount: z.number(),
  note: z.string().nullable().optional(),
});

const transactionCreate = z.object({
  account_id: guid,
  to_account_id: guid.optional(),
  type: z.enum(TRANSACTION_TYPES),
  amount: z.number(),
  category_id: optStr,
  merchant: optStr,
  date: isoDate.optional(),
  description: optStr,
  notes: optStr,
  credit_card_id: optStr,
  loan_id: optStr,
  investment_id: optStr,
  company_id: optStr,
  is_external_to_account: z.boolean().default(false),
  is_cash_spend: z.boolean().default(false),
  tags: z.array(z.string()).default([]),
  splits: z.array(transactionSplitItem).default([]),
}).strict();

const categoryCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(CATEGORY_TYPES),
  parent_id: optStr,
  icon: z.string().trim().min(1).default("tag"),
  color_hex: z.string().trim().min(1).default("0xFF6366F1"),
}).strict();

const creditCardCreate = z.object({
  name: z.string().trim().min(1),
  card_type: z.enum(CARD_TYPES).default("credit"),
  bank: z.string().default(""),
  last4: z.string().regex(/^\d{0,4}$/).default(""),
  network: z.enum(CARD_NETWORKS).default("visa"),
  cardholder_name: z.string().default(""),
  expiry_month: z.number().int().min(1).max(12).optional(),
  expiry_year: z.number().int().min(2000).max(2100).optional(),
  color_preset: z.enum(CARD_COLOR_PRESETS).default("midnight"),
  color_hex: optStr,
  is_virtual: z.boolean().default(false),
  notes: optStr,
  credit_limit: z.number().default(0),
  current_outstanding: z.number().default(0),
  statement_day: z.number().int().min(1).max(31).default(1),
  due_day: z.number().int().min(1).max(31).default(15),
  linked_account_id: optStr,
  balance: z.number().optional(),
  currency: optStr,
  // App-managed reminder bookkeeping (0005_card_last_payment.sql) — readable
  // on list/get, and writable here too (e.g. correcting a missed reminder).
  last_payment_date: isoDate.optional(),
  last_payment_amount: z.number().optional(),
}).strict();

const loanCreate = z.object({
  name: z.string().trim().min(1),
  provider: z.string().default(""),
  principal_amount: z.number().default(0),
  outstanding_amount: z.number().default(0),
  interest_rate: z.number().default(0),
  monthly_emi: z.number().default(0),
  due_day: z.number().int().min(1).max(31).default(1),
  start_date: isoDate.optional(),
  remaining_tenure_months: z.number().int().min(0).default(0),
}).strict();

const budgetCreate = z.object({
  category_id: z.string().trim().min(1),
  monthly_limit: z.number().default(0),
  month_year: z.string().regex(/^\d{4}-\d{2}$/, 'must be "YYYY-MM"'),
  spent_amount: z.number().default(0),
}).strict();

const recurringCreate = z.object({
  title: z.string().trim().min(1),
  amount: z.number().default(0),
  frequency: z.enum(PAYMENT_FREQUENCIES).default("monthly"),
  next_due_date: isoDate,
  category_id: optStr,
  account_id: optStr,
  is_auto_pay: z.boolean().default(false),
  is_income: z.boolean().default(false),
  company_id: optStr,
}).strict();

const investmentCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(INVESTMENT_TYPES).default("other"),
  invested_amount: z.number().default(0),
  current_value: z.number().default(0),
  monthly_sip_amount: z.number().default(0),
  sip_day: z.number().int().min(1).max(31).default(1),
  // "Auto-invest on SIP day" — when true the app auto-posts this SIP monthly.
  auto_invest_enabled: z.boolean().default(false),
  reference_number: optStr,
  // last_auto_posted_month is an app-managed idempotency marker: readable on
  // list/get, but intentionally NOT writable here.
}).strict();

const goalCreate = z.object({
  name: z.string().trim().min(1),
  target_amount: z.number().default(0),
  current_saved_amount: z.number().default(0),
  target_date: isoDate.optional(),
  icon: z.string().trim().min(1).default("target"),
  color_hex: z.string().trim().min(1).default("0xFF6366F1"),
}).strict();

const companyCreate = z.object({
  name: z.string().trim().min(1),
  joined_date: isoDate.optional(),
  is_current_employer: z.boolean().default(false),
  default_bank_account_id: optStr,
  default_pf_amount: z.number().optional(),
}).strict();

export const SPLIT_MODES = ["equal", "custom", "ratio", "percentage"] as const;

const personCreate = z.object({
  name: z.string().trim().min(1),
}).strict();

const splitExpenseCreate = z.object({
  title: z.string().trim().min(1),
  total_amount: z.number().positive(),
  date: isoDate.optional(),
  // No FK — same "no cross-entity FKs" convention as everything else here;
  // the real expense this points at may sync before or after this row.
  transaction_id: z.string().trim().min(1),
  mode: z.enum(SPLIT_MODES).default("equal"),
}).strict();

const splitParticipantCreate = z.object({
  split_expense_id: z.string().trim().min(1),
  person_id: z.string().trim().min(1),
  share_amount: z.number().positive(),
  is_settled: z.boolean().default(false),
  settled_at: isoDate.optional(),
  settled_transaction_id: optStr,
}).strict();

export const ENTITIES = {
  accounts: {
    table: "accounts", displayName: "account", uuidId: true,
    createSchema: accountCreate, updateSchema: accountCreate.partial(),
    omitFields: ["enc_account_number", "enc_ifsc"], derived: "accountBalance",
  },
  transactions: {
    table: "transactions", displayName: "transaction", uuidId: true,
    createSchema: transactionCreate, updateSchema: transactionCreate.partial(),
    // `splits` used to be forced to `[]` here too, back when it wasn't a
    // recognized key on the create schema at all — now that transactionCreate
    // accepts it directly (with its own default), forcing it here would be a
    // no-op at best (parsed.data always wins in the spread order below) and
    // confusing at worst, so it's gone from `fixed`.
    omitFields: ["attachment_path"], fixed: { sync_status: "synced" },
  },
  categories: {
    table: "categories", displayName: "category", uuidId: false,
    createSchema: categoryCreate, updateSchema: categoryCreate.partial(), omitFields: [],
  },
  credit_cards: {
    table: "credit_cards", displayName: "credit card", uuidId: false,
    createSchema: creditCardCreate, updateSchema: creditCardCreate.partial(),
    omitFields: ["enc_card_number", "enc_cvv", "enc_pin"],
  },
  loans: {
    table: "loans", displayName: "loan", uuidId: false,
    createSchema: loanCreate, updateSchema: loanCreate.partial(), omitFields: [],
  },
  budgets: {
    table: "budgets", displayName: "budget", uuidId: false,
    createSchema: budgetCreate, updateSchema: budgetCreate.partial(), omitFields: [],
  },
  recurring_payments: {
    table: "recurring_payments", displayName: "recurring payment", uuidId: false,
    createSchema: recurringCreate, updateSchema: recurringCreate.partial(), omitFields: [],
  },
  investments: {
    table: "investments", displayName: "investment", uuidId: false,
    createSchema: investmentCreate, updateSchema: investmentCreate.partial(), omitFields: [],
  },
  goals: {
    table: "goals", displayName: "goal", uuidId: false,
    createSchema: goalCreate, updateSchema: goalCreate.partial(), omitFields: [],
  },
  companies: {
    table: "companies", displayName: "company", uuidId: false,
    createSchema: companyCreate, updateSchema: companyCreate.partial(), omitFields: [],
  },
  people: {
    table: "people", displayName: "person", uuidId: false,
    createSchema: personCreate, updateSchema: personCreate.partial(), omitFields: [],
  },
  split_expenses: {
    table: "split_expenses", displayName: "split expense", uuidId: false,
    createSchema: splitExpenseCreate, updateSchema: splitExpenseCreate.partial(), omitFields: [],
  },
  split_participants: {
    table: "split_participants", displayName: "split participant", uuidId: false,
    createSchema: splitParticipantCreate, updateSchema: splitParticipantCreate.partial(), omitFields: [],
  },
} satisfies Record<string, EntityDef>;

export type EntityName = keyof typeof ENTITIES;
export const ENTITY_NAMES = Object.keys(ENTITIES) as [EntityName, ...EntityName[]];
