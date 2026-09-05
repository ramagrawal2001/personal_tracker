# EMI-on-Card Linkage & Generic Bill/Payee Reminders — Findings

> Research only — nothing in this doc has been implemented yet. Captured so
> this can be picked up as its own piece of work after the Salary/Company/PF
> build (see `docs/TODO.md`). Written 2026-09-05.

## 1. "My EMI is linked to a card — remind me"

### What the user is asking for
A running EMI (loan installment) that gets auto-debited from, or charged to,
a specific credit/debit card or bank account should be reminded distinctly —
e.g. "this EMI comes out of HDFC card on the 5th," and presumably a heads-up
if that card/account might not be ready for it (limit, balance).

### What already exists
- `LoanModel` (`lib/domain/models/models.dart`) — `id, name, provider,
  principalAmount, outstandingAmount, interestRate, monthlyEmi, dueDay,
  startDate, remainingTenureMonths, updatedAt, isDeleted`. **No link to any
  `CardModel` or `AccountModel` at all** — a loan today is a fully standalone
  entity.
- Reminders for loans already work: `PaymentReminders.compute`
  (`lib/core/services/payment_reminders.dart`) emits a due-soon + due-today
  notification per loan from `dueDay` + `monthlyEmi`, independent of how it's
  actually paid.
- A loan payment is recorded as a normal `TransactionType.loanPayment`
  transaction with `accountId` (the account debited) + `loanId` — so
  *after the fact*, the app knows which account paid an EMI (from
  transaction history), but the loan itself carries no forward-looking
  "this will come out of X" declaration.
- Credit cards already have their own due-date reminder machinery
  (statement/due-soon/due-today, `payment_reminders.dart`), entirely separate
  from loans.

### The gap
1. No field on `LoanModel` (or a new "EMI instrument" concept) declaring
   *which* card or account an EMI is expected to be paid from.
2. No cross-check between "EMI due on day X" and "card statement/due date"
   or "account balance" to flag a real risk (e.g. EMI due 2 days before
   salary usually lands, or card already near its limit).
3. No distinction today between a **loan** (bank loan, EMI charged to a bank
   account) and a **"no-cost EMI" / converted purchase** sitting on a credit
   card's own statement (some banks let you convert a large purchase into
   EMIs that show up as reduced monthly charges on the *same* card, not as a
   separate loan product). The app has no representation of that second
   shape at all right now — it would show up today as one lump
   `TransactionType.expense` on the card, not as an amortizing schedule.

### Design sketch for later
- Add `String? linkedAccountId` and/or `String? linkedCardId` to
  `LoanModel` (mutually-exclusive-in-practice, both optional) — "this EMI is
  expected to be paid from/via X." Same plain-nullable-column,
  no-cross-entity-FK pattern used throughout this codebase (see
  `supabase/migrations/0002_sync_all_entities.sql` header).
- Reminder body enrichment: when a loan has a `linkedAccountId`, the
  due-soon/due-today notification can name the account ("EMI ₹12,000 due
  today from HDFC Savings") and optionally warn if that account's
  `calculatedBalance` looks short of the EMI amount as of "now" (soft
  warning only — balance changes daily, so this is advisory, not a hard
  gate).
- When `linkedCardId` points at a credit card, cross-reference the card's
  own due-date reminders so the two don't read as unrelated, independent
  pings for what is, to the user, one obligation.
- The "no-cost EMI on card" shape (a purchase amortized on the card's own
  statement) is structurally closer to a new `CardEmiModel` (principal,
  remaining installments, monthly installment amount, linked `cardId`) than
  to `LoanModel` — flag as a separate open question rather than assuming
  it reuses `LoanModel`.

### Open questions for the user
1. Is this about (a) a normal bank loan whose EMI happens to auto-debit a
   specific account, (b) a "no-cost EMI" conversion sitting on a credit
   card's own statement, or both?
2. Should a balance/limit shortfall actually block anything, or purely be
   an informational nudge in the reminder text?

## 2. Generic recurring payment reminders ("pay Papa," rent, maid, electricity)

### What already exists — this is mostly built
`RecurringPaymentModel` (`lib/domain/models/models.dart`) + the "Financial
Calendar" screen (`lib/features/recurring/presentation/calendar_screen.dart`)
already supports exactly this shape today:
- Free-text `title` — "Rent," "Maid," "Electricity Bill," or "Payment to
  Papa" all just work as a title today, no payee/person model needed for the
  basic case.
- `frequency` (`PaymentFrequency`: daily/weekly/monthly/quarterly/yearly) —
  this **is** the "reminder frequency" the user is asking for.
- `nextDueDate` — this **is** the "first reminder date" the user is asking
  for (the very first occurrence you set is the first reminder; every
  future occurrence is derived from it + frequency in
  `upcomingPaymentsTotal`/`PaymentReminders.compute`).
- `isAutoPay` (display-only flag, not wired to any automation — confirmed:
  nothing reads it besides display).
- As of the Salary/Company work in this same session: `isIncome` +
  `companyId` (for payday reminders specifically — irrelevant to this
  feature, but now sitting on the same model).
- Reminders: `PaymentReminders.compute` already emits a due-soon (3 days
  before) + due-today notification for every recurring payment, via the
  existing local-notification pipeline (`NotificationService`).

### The actual gap
1. **No reminder *time-of-day* control.** `payment_reminders.dart` hardcodes
   `_reminderHour = 10` (due-soon) and `_dueHour = 9` (due-today) as
   **global constants** — every reminder in the whole app fires at 9am/10am,
   for cards, loans, and recurring payments alike. There is no per-item "remind
   me at 7pm instead" — this is the one genuinely missing piece the user's
   "first reminder date/time" phrasing points at.
2. **No configurable "how many days before" window.** `_daysBefore = 3` is
   also a single global constant, not per-reminder.
3. No first-class "Payee/Person" entity — if the user wants to see "all
   payments to Papa across time" as a rollup (mirroring what the Company
   model now gives salary), that's a real feature gap, not just a reminder
   gap. Today it's only recoverable by matching free-text `title` strings.
4. Discoverability: this flow lives under "Calendar" in the More menu, which
   may not read as "set up a bill/person reminder" to a user looking for
   that specifically — worth a naming/entry-point pass even before any code
   changes.

### Design sketch for later
- Add `TimeOfDay? reminderTime` (or just `int? reminderHour`, matching the
  existing hour-only granularity elsewhere in `payment_reminders.dart`) and
  `int? daysBefore` to `RecurringPaymentModel`, both optional — fall back to
  the current global constants when unset so existing reminders don't change
  behavior silently.
- `PaymentReminders.compute`'s recurring-payment block would read
  `r.reminderHour ?? _reminderHour` / `r.daysBefore ?? _daysBefore` instead
  of the bare constants.
- Optional, larger: a lightweight `PayeeModel` (name only, maybe a default
  category) that `RecurringPaymentModel` and plain transactions can
  reference via `payeeId`, enabling a "total paid to Papa this year" report
  — same shape as `CompanyModel`, reused for people instead of employers.
  Flag as its own decision point (schema cost vs. value) rather than
  bundling it into the time/frequency fix.
- A quick win with zero schema change: rename/re-surface the entry point —
  e.g. an explicit "Add Bill / Person Reminder" action from the Dashboard or
  Transactions screen that opens the exact same `_showRecurringSheet`, so
  the existing feature is actually found by someone asking for "remind me to
  pay the maid."

### Open questions for the user
1. Is a specific time-of-day per reminder (not just a global 9am/10am) the
   main missing piece, or is a dedicated "Payee" entity (spend-by-person
   reporting) actually the goal?
2. Does "first reminder date" mean "the date of the very first payment" (already
   covered by `nextDueDate`) or something else — e.g. "remind me N days before
   the very first occurrence, then use a different cadence after"?
