# Aspyric — Pending Work

> Living list of what's left to build. Update this file whenever new pending
> work is identified or an item is completed — don't let it drift out of
> sync with reality. Detailed design notes live in the linked docs, not
> duplicated here.

## Recently completed (for context — not pending)
- Credit-card due/statement day dropdowns extended to day 31 (were capped at 28).
- Credit-card "Pay With" in Add Transaction — charge a purchase to a credit
  card (bumps outstanding) alongside the existing debit-card flow.
- Edit Card sheet now pre-fills decrypted card number/CVV/PIN instead of
  showing them blank.
- Salary / Company / PF workflow MVP: `CompanyModel` (employer registry, one
  "current employer" at a time), PF via `InvestmentType.epf`, `logSalary`
  (net credit + optional PF contribution without double-debiting the bank
  account), freelance/other income via a relabeled merchant field, and
  payday reminders (`RecurringPaymentModel.isIncome` excluded from
  Safe-to-Spend). See `~/.claude/plans/elegant-forging-mccarthy.md` for the
  full plan this shipped from (Part A there is the full feature roadmap;
  Part B is what actually got built).

## Pending — Salary / Company / PF (Phase 2+)
Full detail: Part A of the plan referenced above.
- [ ] Itemized salary deductions (TDS, insurance, NPS-employer, "other")
      instead of the MVP's net + PF-only breakdown.
- [ ] Versioned salary structure per company (`SalaryStructureModel`:
      effectiveFrom, CTC, default gross/PF%/deductions) so a raise doesn't
      overwrite history.
- [ ] PF withdrawal flow (partial/full) — decrements PF balance, credits a
      bank account, excluded from `monthlyIncome`.
- [ ] PF interest credit (annual) — bumps `currentValue` only, excluded from
      `monthlyIncome`.
- [ ] Bonus / variable pay / reimbursements as an income sub-category tag.
- [ ] Salary & PF analytics (trend per company, take-home-vs-CTC, PF growth
      chart).
- [ ] UAN / PF reference number already has a field (`InvestmentModel.referenceNumber`)
      — just needs surfacing in more places if useful (e.g. dashboard PF tile).
- [ ] Split salary across multiple bank accounts.
- [ ] Dedicated `ProvidentFundModel` with employee-vs-employer contribution
      split (only if compliance-grade PF statements become a real need —
      the MVP deliberately reused Investments instead).
- [ ] Gratuity tracking.
- [ ] Multiple-simultaneous-employers UI polish (schema already allows it).
- [ ] Freelance/gig invoicing (client, invoice number, paid/pending status,
      client-side TDS) — a real mini-invoicing module, bigger than the MVP's
      "Client/Source" text field.
- [ ] Multi-currency freelance income — verify whether per-account currency
      already covers this before building anything new.
- [ ] CSV import mapping for salary rows.
- [ ] Company metadata polish (logo/color, HR contact, employment type).

## Pending — EMI / loan ↔ card linkage
Full detail: `docs/EMI_AND_REMINDERS_FINDINGS.md` §1.
- [ ] Decide: is this about a bank loan whose EMI auto-debits a specific
      account, a "no-cost EMI" conversion sitting on a credit card's own
      statement, or both — needs a user decision before design.
- [ ] Add `linkedAccountId`/`linkedCardId` to `LoanModel` so a reminder can
      name the account/card an EMI is expected to be paid from.
- [ ] Optional soft balance/limit-shortfall warning in the EMI reminder text.
- [ ] If "EMI on card" (case b above) is wanted: new `CardEmiModel` concept
      (principal, remaining installments, monthly installment, linked
      `cardId`) — structurally different from `LoanModel`.

## Pending — Generic bill/payee reminders ("pay Papa," rent, maid, electricity)
Full detail: `docs/EMI_AND_REMINDERS_FINDINGS.md` §2.
- [ ] Confirm with the user whether this is mostly already covered by the
      existing Recurring Payments feature (title + frequency + due date) —
      likely yes for the basic case.
- [ ] Per-reminder time-of-day (`reminderHour`) and days-before-due window —
      today both are global constants (`_reminderHour=10`, `_dueHour=9`,
      `_daysBefore=3` in `payment_reminders.dart`), not configurable per item.
- [ ] Decide whether a dedicated `PayeeModel` (people, not just employers) is
      wanted for spend-by-person reporting, or free-text `title` is enough.
- [ ] Discoverability: consider a clearer entry point (e.g. "Add Bill/Person
      Reminder") rather than only "Calendar" in the More menu.

## Process note
When picking any of the above back up: re-read the relevant findings doc
first, verify the facts against current source (models/tables may have
moved since this was written), then follow the same plan-mode workflow used
for the Salary/Company/PF work before touching code.
