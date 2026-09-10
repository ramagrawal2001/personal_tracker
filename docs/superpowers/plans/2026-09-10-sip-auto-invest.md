# SIP Auto-Invest & Recurring Surfacing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give SIP investments EMI-style recurring treatment — due reminders, a dashboard tile, calendar rows — plus a new per-investment "Auto-invest on SIP day" toggle that auto-posts the SIP transaction once a month from a user-chosen account.

**Architecture:** Approach A from the spec. Two new columns on `investments` (`auto_invest_enabled`, `last_auto_posted_month`) + a device-local `sipDebitAccountId` pref. A new idempotent `FinanceNotifier.processDueSipAutoPosts()` reuses the existing `addTransaction(type: investment)` side-effect and runs on load + app resume. Reminders/calendar/dashboard read SIPs regardless of the toggle. SIP outflows never touch Safe-to-Spend.

**Tech Stack:** Flutter, Riverpod `StateNotifier`, Drift (SQLite) + codegen, Supabase (PostgREST), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-10-sip-auto-invest-design.md` — read it with this plan.

## Global Constraints

- **Package name** is `aspyric` — test imports are `package:aspyric/...`.
- **Enum wire values** are Dart enum `.name`. Investment SIP transactions use `TransactionType.investment` and category id `cat_investment` ("Investment / SIP", a default category).
- **Drift migrations are defensive** — follow the existing `addColumnIfMissing` pattern in `lib/core/database/app_database.dart`; a synthetic-upgrade test harness may already be on the current schema.
- **Cloud writes go straight to Supabase** via `pushToCloud` (returns `null` for demo/offline accounts, throws `CloudWriteException` when a real session's write fails). Never assume a write succeeded without checking.
- **Soft deletes only** (`isDeleted` / tombstones). Never hard-delete.
- **Idempotency marker** `last_auto_posted_month` is `"YYYY-MM"` (`now.month` zero-padded to 2). It syncs; a second device must see it and skip.
- **Auto-post is inert when `sipDebitAccountId` is null or names a missing/deleted account.**
- **Every task ends with `flutter analyze` clean and the named tests green, then a commit.** Commit prefixes: `feat(sip):`, `test(sip):`, `chore(sip):`.
- Codegen: `dart run build_runner build --delete-conflicting-outputs` after touching Drift tables. Commit the regenerated `*.g.dart`.
- Do **not** touch `personal-tracker-mcp/` — unrelated.

---

## File structure

| File | Change |
|---|---|
| `supabase/migrations/0008_sip_autopost.sql` | new — 2 columns on `investments` |
| `lib/core/database/tables.dart` | `Investments`: `autoInvestEnabled`, `lastAutoPostedMonth` |
| `lib/core/database/app_database.dart` | `schemaVersion` 8→9 + `from < 9` block |
| `lib/core/database/app_database.g.dart` | regenerated |
| `lib/domain/models/models.dart` | `InvestmentModel` fields + ctor + `copyWith` |
| `lib/core/database/finance_mappers.dart` | investment `toModel` / `toCompanion` |
| `lib/core/sync/cloud_mappers.dart` | `InvestmentCloud` json + `kPrefSipDebitAccount` |
| `lib/core/database/finance_repository.dart` | `FinanceState` (`sipDebitAccountId`, `upcomingObligations`, `UpcomingObligation`, `ObligationKind`); `FinanceNotifier` (`processDueSipAutoPosts`, `setSipDebitAccount`, `addInvestment`/`updateInvestment` params, load hook); `financeNotifierProvider` signature |
| `lib/core/services/payment_reminders.dart` | SIP reminder block |
| `lib/features/navigation/main_shell.dart` | resume → `processDueSipAutoPosts` |
| `lib/features/dashboard/presentation/widgets/money_summary_card.dart` | `upcomingSips` + 2×2 tiles |
| `lib/features/dashboard/presentation/dashboard_screen.dart` | pass `upcomingSips` ×2 |
| `lib/features/recurring/presentation/calendar_screen.dart` | consume `upcomingObligations` |
| `lib/features/investments/presentation/add_investment_modal.dart` | auto-invest switch |
| `lib/features/investments/presentation/investments_screen.dart` | edit sheet: SIP day + switch |
| `lib/features/settings/presentation/settings_screen.dart` | SIP debit account dropdown |
| `test/sip_schema_test.dart`, `test/sip_reminders_test.dart`, `test/upcoming_obligations_test.dart`, `test/sip_auto_post_test.dart` | new tests |

---

## Task 1: Investment schema — new fields end to end

**Files:**
- Create: `supabase/migrations/0008_sip_autopost.sql`
- Modify: `lib/core/database/tables.dart` (`Investments` table)
- Modify: `lib/core/database/app_database.dart` (`schemaVersion`, migration)
- Modify: `lib/domain/models/models.dart` (`InvestmentModel`)
- Modify: `lib/core/database/finance_mappers.dart` (investment mappers)
- Modify: `lib/core/sync/cloud_mappers.dart` (`InvestmentCloud`)
- Regenerate: `lib/core/database/app_database.g.dart`
- Modify: `lib/core/database/finance_repository.dart` (`addInvestment` / `updateInvestment` params only)
- Test: `test/sip_schema_test.dart`

**Interfaces:**
- Produces:
  - `InvestmentModel.autoInvestEnabled` (`bool`, default `false`), `InvestmentModel.lastAutoPostedMonth` (`String?`) — as final fields, ctor named params, and `copyWith` named params.
  - `FinanceNotifier.addInvestment({..., bool autoInvestEnabled = false})`
  - `FinanceNotifier.updateInvestment(String id, {..., int? sipDay, bool? autoInvestEnabled, String? lastAutoPostedMonth})`
  - Drift columns `investments.auto_invest_enabled` (bool, default false), `investments.last_auto_posted_month` (text, nullable).
  - Cloud JSON keys `auto_invest_enabled`, `last_auto_posted_month`.

- [ ] **Step 1: Write the failing test — `test/sip_schema_test.dart`**

```dart
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InvestmentModel sample() => InvestmentModel(
        id: 'i1',
        name: 'Nifty 50',
        type: InvestmentType.mutualFundSip,
        investedAmount: 100000,
        currentValue: 115000,
        monthlySipAmount: 5000,
        sipDay: 7,
        autoInvestEnabled: true,
        lastAutoPostedMonth: '2026-09',
      );

  test('copyWith carries the new fields and can toggle them', () {
    final a = sample();
    expect(a.autoInvestEnabled, isTrue);
    expect(a.lastAutoPostedMonth, '2026-09');
    final b = a.copyWith(autoInvestEnabled: false, lastAutoPostedMonth: '2026-10');
    expect(b.autoInvestEnabled, isFalse);
    expect(b.lastAutoPostedMonth, '2026-10');
    // unspecified → unchanged
    expect(a.copyWith(name: 'x').autoInvestEnabled, isTrue);
  });

  test('defaults when omitted', () {
    final m = InvestmentModel(
      id: 'i2', name: 'x', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0,
    );
    expect(m.autoInvestEnabled, isFalse);
    expect(m.lastAutoPostedMonth, isNull);
  });

  test('Drift round-trip preserves the new fields', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.investments).insertOnConflictUpdate(sample().toCompanion());
    final row = await (db.select(db.investments)..where((t) => t.id.equals('i1'))).getSingle();
    final back = row.toModel();
    expect(back.autoInvestEnabled, isTrue);
    expect(back.lastAutoPostedMonth, '2026-09');
    await db.close();
  });

  test('cloud JSON round-trip preserves the new fields', () {
    final json = sample().toCloudJson();
    expect(json['auto_invest_enabled'], true);
    expect(json['last_auto_posted_month'], '2026-09');
    final back = InvestmentCloud.fromCloud({
      ...json,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(back.autoInvestEnabled, isTrue);
    expect(back.lastAutoPostedMonth, '2026-09');
  });

  test('cloud fromCloud tolerates the columns being absent (old project)', () {
    final back = InvestmentCloud.fromCloud({
      'id': 'i3', 'name': 'x', 'type': 'other',
      'invested_amount': 0, 'current_value': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(back.autoInvestEnabled, isFalse);
    expect(back.lastAutoPostedMonth, isNull);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/sip_schema_test.dart`
Expected: compile errors — `autoInvestEnabled` / `lastAutoPostedMonth` not defined on `InvestmentModel`.

- [ ] **Step 3: Add the fields to `InvestmentModel`** (`lib/domain/models/models.dart`, class `InvestmentModel`)

After `final int sipDay;` add:
```dart
  final bool autoInvestEnabled;
  final String? lastAutoPostedMonth; // "YYYY-MM" of the last auto-post
```
In the constructor param list (after `this.sipDay = 1,`):
```dart
    this.autoInvestEnabled = false,
    this.lastAutoPostedMonth,
```
In `copyWith` params (after `int? sipDay,`):
```dart
    bool? autoInvestEnabled,
    String? lastAutoPostedMonth,
```
In the `copyWith` body's `InvestmentModel(...)` (after `sipDay: sipDay ?? this.sipDay,`):
```dart
      autoInvestEnabled: autoInvestEnabled ?? this.autoInvestEnabled,
      lastAutoPostedMonth: lastAutoPostedMonth ?? this.lastAutoPostedMonth,
```

- [ ] **Step 4: Add the Drift columns** (`lib/core/database/tables.dart`, class `Investments`)

After `IntColumn get sipDay => integer().withDefault(const Constant(1))();` add:
```dart
  BoolColumn get autoInvestEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get lastAutoPostedMonth => text().nullable()();
```

- [ ] **Step 5: Bump schema version + migration** (`lib/core/database/app_database.dart`)

Change `int get schemaVersion => 8;` → `9`.
At the end of the `onUpgrade` callback, after the `if (from < 8)` block, add:
```dart
          if (from < 9) {
            // v9: SIP auto-invest (per-investment toggle + monthly idempotency marker).
            final existing = (await customSelect('PRAGMA table_info(investments)').get())
                .map((row) => row.read<String>('name'))
                .toSet();
            if (!existing.contains(investments.autoInvestEnabled.name)) {
              await m.addColumn(investments, investments.autoInvestEnabled);
            }
            if (!existing.contains(investments.lastAutoPostedMonth.name)) {
              await m.addColumn(investments, investments.lastAutoPostedMonth);
            }
          }
```

- [ ] **Step 6: Update the Drift mappers** (`lib/core/database/finance_mappers.dart`)

In `InvestmentEntryMapper.toModel()` add (after `sipDay: sipDay,`):
```dart
      autoInvestEnabled: autoInvestEnabled,
      lastAutoPostedMonth: lastAutoPostedMonth,
```
In `InvestmentModelMapper.toCompanion()` add (after `sipDay: Value(sipDay),`):
```dart
      autoInvestEnabled: Value(autoInvestEnabled),
      lastAutoPostedMonth: Value(lastAutoPostedMonth),
```

- [ ] **Step 7: Update the cloud mapper** (`lib/core/sync/cloud_mappers.dart`, `extension InvestmentCloud`)

In `toCloudJson()` add (after `'sip_day': sipDay,`):
```dart
        'auto_invest_enabled': autoInvestEnabled,
        'last_auto_posted_month': lastAutoPostedMonth,
```
In `fromCloud(...)` add (after `sipDay: _int(m['sip_day'] ?? 1),`):
```dart
        autoInvestEnabled: _bool(m['auto_invest_enabled']),
        lastAutoPostedMonth: m['last_auto_posted_month'] as String?,
```

- [ ] **Step 8: Add params to `addInvestment` / `updateInvestment`** (`lib/core/database/finance_repository.dart`)

`addInvestment(...)` — add param `bool autoInvestEnabled = false,` and pass `autoInvestEnabled: autoInvestEnabled` into the `InvestmentModel(...)` draft.

`updateInvestment(String id, {...})` — add params:
```dart
    int? sipDay,
    bool? autoInvestEnabled,
    String? lastAutoPostedMonth,
```
and pass them into the `existing.first.copyWith(...)` call:
```dart
      sipDay: sipDay,
      autoInvestEnabled: autoInvestEnabled,
      lastAutoPostedMonth: lastAutoPostedMonth,
```

- [ ] **Step 9: Write the migration SQL — `supabase/migrations/0008_sip_autopost.sql`**

```sql
-- 0008_sip_autopost.sql
--
-- SIP auto-invest: a per-investment "auto-invest on SIP day" toggle and a
-- month-granularity idempotency marker so the client posts each SIP at most
-- once per calendar month, across devices.
--
-- Backward compatible; nullable / defaulted. Apply with: supabase db push

alter table public.investments
  add column if not exists auto_invest_enabled boolean not null default false,
  add column if not exists last_auto_posted_month text;
```

- [ ] **Step 10: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` updated with the two new columns on `InvestmentEntry` / `InvestmentsCompanion`.

- [ ] **Step 11: Run tests + analyze**

Run: `flutter test test/sip_schema_test.dart test/migration_check_test.dart`
Expected: PASS (both).
Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 12: Commit**

```bash
git add supabase/migrations/0008_sip_autopost.sql lib/core/database/ lib/domain/models/models.dart lib/core/sync/cloud_mappers.dart test/sip_schema_test.dart
git commit -m "feat(sip): investment auto-invest + last-auto-posted-month columns"
```

---

## Task 2: Device-local `sipDebitAccountId`

**Files:**
- Modify: `lib/core/sync/cloud_mappers.dart` (pref key constant)
- Modify: `lib/core/database/finance_repository.dart` (`FinanceState` field, `setSipDebitAccount`, load)
- Test: extend `test/sip_schema_test.dart` (or add to a repo test) — see step 1

**Interfaces:**
- Consumes: `SharedPreferences`.
- Produces:
  - `const String kPrefSipDebitAccount = 'finance_sip_debit_account_id';` (exported from `cloud_mappers.dart` next to the other `kPref*`).
  - `FinanceState.sipDebitAccountId` (`String?`, default `null`), threaded through `copyWith` and `_emptyState()`.
  - `FinanceNotifier.setSipDebitAccount(String? accountId)` — updates state and writes the pref (removes the key when `null`). No cloud push.
  - `_loadPersistedState()` reads the pref into state.

- [ ] **Step 1: Write the failing test — append to `test/sip_schema_test.dart`**

```dart
// add these imports at the top if missing:
// import 'package:aspyric/core/database/finance_repository.dart';
// import 'package:shared_preferences/shared_preferences.dart';

  group('sipDebitAccountId', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setSipDebitAccount updates state and persists', () async {
      final n = FinanceNotifier(AppDatabase.forTesting(NativeDatabase.memory()), autoLoad: false);
      expect(n.state.sipDebitAccountId, isNull);
      await n.setSipDebitAccount('acc-1');
      expect(n.state.sipDebitAccountId, 'acc-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('finance_sip_debit_account_id'), 'acc-1');
      await n.setSipDebitAccount(null);
      expect(n.state.sipDebitAccountId, isNull);
      expect(prefs.getString('finance_sip_debit_account_id'), isNull);
    });
  });
```

- [ ] **Step 2: Run it — confirm failure**

Run: `flutter test test/sip_schema_test.dart`
Expected: FAIL — `sipDebitAccountId` / `setSipDebitAccount` undefined.

- [ ] **Step 3: Add the pref key** (`lib/core/sync/cloud_mappers.dart`, near `kPrefEmergencyBuffer` et al.)

```dart
const String kPrefSipDebitAccount = 'finance_sip_debit_account_id';
```

- [ ] **Step 4: Add `FinanceState.sipDebitAccountId`** (`lib/core/database/finance_repository.dart`, class `FinanceState`)

Add field `final String? sipDebitAccountId;`, constructor param `this.sipDebitAccountId,`, `copyWith` param `String? sipDebitAccountId,` and body line `sipDebitAccountId: sipDebitAccountId ?? this.sipDebitAccountId,`. In `_emptyState()` nothing needed (nullable defaults to `null`); confirm the `FinanceState(...)` there compiles without it (named optional).

- [ ] **Step 5: Add `setSipDebitAccount`** (in `FinanceNotifier`, near `updateEmergencyBuffer`)

```dart
  /// The single account SIP auto-posts debit. Device-local (SharedPreferences),
  /// not cloud-synced — the synced `lastAutoPostedMonth` marker is what keeps
  /// two devices from double-posting.
  Future<void> setSipDebitAccount(String? accountId) async {
    state = state.copyWith(sipDebitAccountId: accountId);
    final prefs = await SharedPreferences.getInstance();
    if (accountId == null) {
      await prefs.remove(kPrefSipDebitAccount);
    } else {
      await prefs.setString(kPrefSipDebitAccount, accountId);
    }
  }
```
> Note: `state.copyWith(sipDebitAccountId: null)` cannot clear a value through the `?? this` pattern. Handle the null case explicitly: in `setSipDebitAccount`, when `accountId == null`, use a dedicated clear — either add a `bool clearSipDebitAccount` to `copyWith`, or set `state = FinanceState(... existing fields ..., sipDebitAccountId: null)` via a small private helper. Simplest: give `copyWith` a `bool clearSipDebitAccount = false` flag and honour it.

- [ ] **Step 6: Load the pref** (`_loadPersistedState()` — where `emergencyBuffer` / `currencySymbol` are read from prefs)

Add to the `copyWith` / state build that reads prefs:
```dart
        sipDebitAccountId: prefs.getString(kPrefSipDebitAccount),
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/sip_schema_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add lib/core/ test/sip_schema_test.dart
git commit -m "feat(sip): device-local sipDebitAccountId setting"
```

---

## Task 3: SIP due reminders

**Files:**
- Modify: `lib/core/services/payment_reminders.dart` (SIP block)
- Modify: `lib/core/database/finance_repository.dart` (`financeNotifierProvider` signature string)
- Test: `test/sip_reminders_test.dart`

**Interfaces:**
- Consumes: `FinanceState.investments`, `InvestmentModel.{sipDay, monthlySipAmount, autoInvestEnabled, isDeleted, name}`.
- Produces: two `ReminderSpec`s per investment with `monthlySipAmount > 0` and `!isDeleted` — ids `idFor('sip_<id>', _Kind.dueSoon.index)` and `idFor('sip_<id>', _Kind.dueToday.index)`. `dueSoon` is emitted only when it is still in the future.

- [ ] **Step 1: Write the failing test — `test/sip_reminders_test.dart`**

```dart
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/payment_reminders.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 10, 8);

  FinanceState stateWith(List<InvestmentModel> investments) => FinanceState(
        accounts: const [], categories: const [], transactions: const [],
        creditCards: const [], loans: const [], budgets: const [],
        recurringPayments: const [], investments: investments, goals: const [],
      );

  InvestmentModel sip({
    String id = 'i1',
    double amount = 5000,
    int day = 20,
    bool auto = false,
    bool deleted = false,
  }) =>
      InvestmentModel(
        id: id, name: 'Nifty 50', type: InvestmentType.mutualFundSip,
        investedAmount: 0, currentValue: 0,
        monthlySipAmount: amount, sipDay: day,
        autoInvestEnabled: auto, isDeleted: deleted,
      );

  test('a SIP gets due-soon + due-today on its sipDay', () {
    final r = PaymentReminders.compute(stateWith([sip(day: 20)]), now);
    final sipR = r.where((e) => e.title.contains('SIP')).toList();
    expect(sipR.length, 2);
    final today = sipR.firstWhere((e) => e.title.contains('today'));
    expect(today.when, DateTime(2026, 6, 20, 9));
    final soon = sipR.firstWhere((e) => e.title.contains('soon'));
    expect(soon.when, DateTime(2026, 6, 17, 10));
  });

  test('auto-invest wording differs from manual', () {
    final auto = PaymentReminders.compute(stateWith([sip(auto: true)]), now);
    expect(auto.any((e) => e.title.contains('auto-invests')), isTrue);
    final manual = PaymentReminders.compute(stateWith([sip(auto: false)]), now);
    expect(manual.any((e) => e.title.contains('SIP due')), isTrue);
    expect(manual.any((e) => e.title.contains('auto-invests')), isFalse);
  });

  test('zero SIP amount or deleted investment → no reminders', () {
    expect(PaymentReminders.compute(stateWith([sip(amount: 0)]), now)
        .where((e) => e.id != 0), isEmpty);
    expect(PaymentReminders.compute(stateWith([sip(deleted: true)]), now)
        .where((e) => e.id != 0), isEmpty);
  });

  test('sipDay already past this month rolls to next month', () {
    final r = PaymentReminders.compute(stateWith([sip(day: 5)]), now);
    final today = r.firstWhere((e) => e.title.contains('today'));
    expect(today.when, DateTime(2026, 7, 5, 9));
  });

  test('due-soon suppressed when it is already in the past', () {
    // sipDay 11: due 11 Jun, soon = 8 Jun (before now) → only due-today.
    final r = PaymentReminders.compute(stateWith([sip(day: 11)]), now)
        .where((e) => e.title.contains('SIP')).toList();
    expect(r.length, 1);
    expect(r.single.title.contains('today'), isTrue);
  });

  test('ids are stable, non-zero, and namespaced away from loans', () {
    final r1 = PaymentReminders.compute(stateWith([sip()]), now);
    final r2 = PaymentReminders.compute(stateWith([sip()]), now);
    expect(r1.map((e) => e.id).toList(), r2.map((e) => e.id).toList());
    expect(r1.every((e) => e.id != 0), isTrue);
    expect(r1.map((e) => e.id).toSet().length, r1.length);
  });
}
```

- [ ] **Step 2: Run it — confirm failure**

Run: `flutter test test/sip_reminders_test.dart`
Expected: FAIL — no SIP reminders produced (expected lengths are 0).

- [ ] **Step 3: Add the SIP block** (`lib/core/services/payment_reminders.dart`)

Immediately after the `// ── Loans (EMI) ──` `for` loop and before `// ── Recurring payments ──`, insert:

```dart
    // ── SIPs (investments with a monthly SIP) ───────────────────────────
    for (final inv in state.investments) {
      if (inv.isDeleted) continue;
      if (inv.monthlySipAmount <= 0) continue;
      final due = inv.sipDay.clamp(1, 31);
      final dueDate = nextOnDay(due, now, _dueHour);
      final soon = dueDate.subtract(const Duration(days: _daysBefore))
          .copyWithHour(_reminderHour);
      final auto = inv.autoInvestEnabled;
      if (soon.isAfter(now)) {
        out.add(ReminderSpec(
          id: idFor('sip_${inv.id}', _Kind.dueSoon.index),
          when: soon,
          title: auto
              ? '🔁 ${inv.name} SIP auto-invests soon'
              : '${inv.name} SIP due soon',
          body: auto
              ? '${_amt(inv.monthlySipAmount)} will be invested in $_daysBefore days.'
              : '${_amt(inv.monthlySipAmount)} SIP due in $_daysBefore days.',
        ));
      }
      out.add(ReminderSpec(
        id: idFor('sip_${inv.id}', _Kind.dueToday.index),
        when: dueDate,
        title: auto
            ? '🔁 ${inv.name} SIP auto-invests today'
            : '${inv.name} SIP due today',
        body: auto
            ? 'Investing ${_amt(inv.monthlySipAmount)} automatically.'
            : 'Invest ${_amt(inv.monthlySipAmount)} — log it in Investments.',
      ));
    }
```

- [ ] **Step 4: Add SIPs to the scheduler signature** (`lib/core/database/finance_repository.dart`, `financeNotifierProvider` → `notifier.onStateChanged`)

Inside the list literal that builds `sig`, after the `for (final r in s.recurringPayments) ...` line, add:
```dart
      for (final i in s.investments)
        if (!i.isDeleted && i.monthlySipAmount > 0)
          'S${i.id}:${i.sipDay}:${i.monthlySipAmount}:${i.autoInvestEnabled}',
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/sip_reminders_test.dart test/card_reminders_test.dart`
Expected: PASS (both — the existing card/loan/recurring tests must stay green).
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/payment_reminders.dart lib/core/database/finance_repository.dart test/sip_reminders_test.dart
git commit -m "feat(sip): SIP due reminders mirroring the EMI block"
```

---

## Task 4: `upcomingObligations` merged view

**Files:**
- Modify: `lib/core/database/finance_repository.dart` (`ObligationKind`, `UpcomingObligation`, `FinanceState.upcomingObligations`)
- Test: `test/upcoming_obligations_test.dart`

**Interfaces:**
- Produces (top-level in `finance_repository.dart`):
  ```dart
  enum ObligationKind { recurring, sip }

  class UpcomingObligation {
    final String id;         // recurring id, or 'sip_<investmentId>'
    final String sourceId;   // the recurring payment id, or the investment id
    final ObligationKind kind;
    final String title;
    final double amount;
    final DateTime date;
    final bool isIncome;     // always false for sip
    const UpcomingObligation({required this.id, required this.sourceId,
      required this.kind, required this.title, required this.amount,
      required this.date, this.isIncome = false});
  }
  ```
- Produces (on `FinanceState`):
  `List<UpcomingObligation> upcomingObligations(DateTime monthAnchor)` — recurring items at their `nextDueDate` (unchanged), plus one SIP item per non-deleted investment with `monthlySipAmount > 0`, dated `monthAnchor`'s year/month with day = `sipDay` clamped to that month's length. Sorted ascending by `date`; deleted rows excluded.

- [ ] **Step 1: Write the failing test — `test/upcoming_obligations_test.dart`**

```dart
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceState stateWith({
    List<RecurringPaymentModel> recurring = const [],
    List<InvestmentModel> investments = const [],
  }) =>
      FinanceState(
        accounts: const [], categories: const [], transactions: const [],
        creditCards: const [], loans: const [], budgets: const [],
        recurringPayments: recurring, investments: investments, goals: const [],
      );

  final anchor = DateTime(2026, 2, 1); // Feb 2026 (28 days)

  test('merges recurring + SIP, sorted by date', () {
    final rec = RecurringPaymentModel(
      id: 'r1', title: 'Rent', amount: 25000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 5),
    );
    final inv = InvestmentModel(
      id: 'i1', name: 'Nifty 50', type: InvestmentType.mutualFundSip,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 5000, sipDay: 3,
    );
    final out = stateWith(recurring: [rec], investments: [inv]).upcomingObligations(anchor);
    expect(out.map((o) => o.kind), [ObligationKind.sip, ObligationKind.recurring]);
    expect(out.first.id, 'sip_i1');
    expect(out.first.date, DateTime(2026, 2, 3));
    expect(out.first.amount, 5000);
    expect(out.first.isIncome, isFalse);
    expect(out.last.title, 'Rent');
  });

  test('SIP day is clamped to the anchor month length', () {
    final inv = InvestmentModel(
      id: 'i1', name: 'X', type: InvestmentType.mutualFundSip,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 1000, sipDay: 31,
    );
    final out = stateWith(investments: [inv]).upcomingObligations(anchor);
    expect(out.single.date, DateTime(2026, 2, 28));
  });

  test('deleted / zero-amount SIPs and deleted recurring are excluded', () {
    final inv0 = InvestmentModel(id: 'i0', name: 'z', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 0, sipDay: 5);
    final invD = InvestmentModel(id: 'iD', name: 'z', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 500, sipDay: 5, isDeleted: true);
    final recD = RecurringPaymentModel(id: 'rD', title: 'gone', amount: 1,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 9), isDeleted: true);
    expect(stateWith(recurring: [recD], investments: [inv0, invD]).upcomingObligations(anchor), isEmpty);
  });

  test('income recurring keeps its isIncome flag', () {
    final pay = RecurringPaymentModel(id: 'p', title: 'Salary', amount: 90000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 25), isIncome: true);
    final out = stateWith(recurring: [pay]).upcomingObligations(anchor);
    expect(out.single.isIncome, isTrue);
  });
}
```

- [ ] **Step 2: Run it — confirm failure**

Run: `flutter test test/upcoming_obligations_test.dart`
Expected: FAIL — `ObligationKind` / `UpcomingObligation` / `upcomingObligations` undefined.

- [ ] **Step 3: Add the types + getter** (`lib/core/database/finance_repository.dart`)

Add the `enum ObligationKind` and `class UpcomingObligation` from the Interfaces block at top level (near the other top-level model-ish declarations, e.g. just above `class FinanceState`).

Inside `class FinanceState`, near `upcomingPaymentsTotal`:
```dart
  /// Recurring payments + SIP occurrences for [monthAnchor]'s month, merged and
  /// sorted by date. Used by the Financial Calendar. SIP entries are always
  /// outflows (isIncome: false) and never affect Safe-to-Spend.
  List<UpcomingObligation> upcomingObligations(DateTime monthAnchor) {
    final out = <UpcomingObligation>[];
    for (final r in recurringPayments) {
      if (r.isDeleted) continue;
      out.add(UpcomingObligation(
        id: r.id, sourceId: r.id, kind: ObligationKind.recurring,
        title: r.title, amount: r.amount, date: r.nextDueDate, isIncome: r.isIncome,
      ));
    }
    final lastDay = DateTime(monthAnchor.year, monthAnchor.month + 1, 0).day;
    for (final inv in investments) {
      if (inv.isDeleted) continue;
      if (inv.monthlySipAmount <= 0) continue;
      out.add(UpcomingObligation(
        id: 'sip_${inv.id}', sourceId: inv.id, kind: ObligationKind.sip,
        title: '${inv.name} SIP', amount: inv.monthlySipAmount,
        date: DateTime(monthAnchor.year, monthAnchor.month, inv.sipDay.clamp(1, lastDay)),
      ));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/upcoming_obligations_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/core/database/finance_repository.dart test/upcoming_obligations_test.dart
git commit -m "feat(sip): upcomingObligations — recurring + SIP merged view"
```

---

## Task 5: `processDueSipAutoPosts` runner

**Files:**
- Modify: `lib/core/database/finance_repository.dart` (`FinanceNotifier.processDueSipAutoPosts`, `_sipAutoPostRunning`)
- Test: `test/sip_auto_post_test.dart`

**Interfaces:**
- Consumes: `state.sipDebitAccountId`, `state.accounts`, `state.investments`, `state.transactions`, `addTransaction(...)`, `updateInvestment(...)`.
- Produces: `Future<void> processDueSipAutoPosts([DateTime? clock])` — idempotent; no-op when no valid debit account; posts at most one `TransactionType.investment` transaction per enabled SIP per calendar month, tagged `'sip-auto'`, categorised `cat_investment`, dated the SIP day, then sets `lastAutoPostedMonth`.

- [ ] **Step 1: Write the failing test — `test/sip_auto_post_test.dart`**

```dart
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FinanceNotifier n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    n = FinanceNotifier(AppDatabase.forTesting(NativeDatabase.memory()), autoLoad: false);
    await n.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 100000);
  });

  String accId() => n.state.accounts.first.id;

  Future<void> addSip({double amount = 5000, int day = 5, bool auto = true}) =>
      n.addInvestment(
        name: 'Nifty 50', type: InvestmentType.mutualFundSip,
        investedAmount: 0, currentValue: 0,
        monthlySipAmount: amount, sipDay: day, autoInvestEnabled: auto,
      );

  final afterSipDay = DateTime(2026, 6, 10, 12); // sipDay 5 has passed
  final beforeSipDay = DateTime(2026, 6, 3, 12);

  test('posts once when due, enabled, account configured', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);

    final txns = n.state.transactions.where((t) => t.tags.contains('sip-auto')).toList();
    expect(txns.length, 1);
    expect(txns.single.amount, 5000);
    expect(txns.single.accountId, accId());
    expect(txns.single.type, TransactionType.investment);
    expect(txns.single.date, DateTime(2026, 6, 5));
    expect(n.state.investments.first.lastAutoPostedMonth, '2026-06');
    // side-effect: currentValue rose by the SIP amount
    expect(n.state.investments.first.currentValue, 5000);
  });

  test('no-op before the SIP day', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(beforeSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);
    expect(n.state.investments.first.lastAutoPostedMonth, isNull);
  });

  test('no-op when disabled / zero amount / no account / account deleted', () async {
    await addSip(auto: false);
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);

    await n.updateInvestment(n.state.investments.first.id, autoInvestEnabled: true, monthlySipAmount: 0);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);

    await n.setSipDebitAccount(null);
    await n.updateInvestment(n.state.investments.first.id, monthlySipAmount: 5000);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);
  });

  test('second call in the same month is a no-op', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);
    await n.processDueSipAutoPosts(afterSipDay.add(const Duration(days: 1)));
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')).length, 1);
  });

  test('ledger backstop: an existing sip-auto txn without the marker just sets the marker', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    final invId = n.state.investments.first.id;
    // simulate a crash-after-post: post the txn manually, leave marker null
    await n.addTransaction(
      accountId: accId(), type: TransactionType.investment, amount: 5000,
      date: DateTime(2026, 6, 5), investmentId: invId, tags: const ['sip-auto'],
    );
    expect(n.state.investments.first.lastAutoPostedMonth, isNull);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')).length, 1); // no second
    expect(n.state.investments.first.lastAutoPostedMonth, '2026-06');
  });

  test('sipDay clamps to the month length', () async {
    await addSip(day: 31);
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(DateTime(2026, 6, 30, 12)); // June has 30 days
    final t = n.state.transactions.firstWhere((t) => t.tags.contains('sip-auto'));
    expect(t.date, DateTime(2026, 6, 30));
  });
```

- [ ] **Step 2: Run it — confirm failure**

Run: `flutter test test/sip_auto_post_test.dart`
Expected: FAIL — `processDueSipAutoPosts` undefined.

- [ ] **Step 3: Implement the runner** (`lib/core/database/finance_repository.dart`, in `FinanceNotifier`)

Add a private field near the top of the class: `bool _sipAutoPostRunning = false;`

Add the method (near `updateInvestment`):

```dart
  /// Posts this month's SIP for every enabled investment whose sipDay has
  /// arrived and that has not been auto-posted this month. Idempotent — safe to
  /// call on every load / resume. No-op without a valid debit account.
  Future<void> processDueSipAutoPosts([DateTime? clock]) async {
    if (_sipAutoPostRunning) return;
    final now = clock ?? DateTime.now();
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final accountId = state.sipDebitAccountId;
    if (accountId == null) return;
    final accountOk = state.accounts.any((a) => a.id == accountId && !a.isDeleted);
    if (!accountOk) return;

    _sipAutoPostRunning = true;
    try {
      for (final inv in List<InvestmentModel>.from(state.investments)) {
        if (inv.isDeleted || !inv.autoInvestEnabled || inv.monthlySipAmount <= 0) {
          continue;
        }
        if (inv.lastAutoPostedMonth == monthKey) continue;

        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        final sipDate =
            DateTime(now.year, now.month, inv.sipDay.clamp(1, lastDay));
        if (now.isBefore(sipDate)) continue;

        final alreadyPosted = state.transactions.any((t) =>
            !t.isDeleted &&
            t.type == TransactionType.investment &&
            t.investmentId == inv.id &&
            t.tags.contains('sip-auto') &&
            t.date.year == now.year &&
            t.date.month == now.month);
        if (alreadyPosted) {
          await updateInvestment(inv.id, lastAutoPostedMonth: monthKey);
          continue;
        }

        try {
          await addTransaction(
            accountId: accountId,
            type: TransactionType.investment,
            amount: inv.monthlySipAmount,
            categoryId: 'cat_investment',
            date: sipDate,
            description: 'Auto SIP — ${inv.name}',
            tags: const ['sip-auto'],
            investmentId: inv.id,
          );
          await updateInvestment(inv.id, lastAutoPostedMonth: monthKey);
        } catch (e) {
          debugPrint('FinanceNotifier.processDueSipAutoPosts(${inv.id}) failed: $e');
          // leave the month unmarked — retried on the next load / resume
        }
      }
    } finally {
      _sipAutoPostRunning = false;
    }
  }
```

> `debugPrint` needs `import 'package:flutter/foundation.dart';` — check it is already imported in this file (it is used elsewhere here). If not, add it.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/sip_auto_post_test.dart`
Expected: PASS (all cases).
Run: `flutter test` (full suite — no regressions in `crud_sweep`, `finance_engine`, etc.)
Expected: PASS.
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/core/database/finance_repository.dart test/sip_auto_post_test.dart
git commit -m "feat(sip): processDueSipAutoPosts — idempotent monthly auto-post"
```

---

## Task 6: Wire the runner into load + resume

**Files:**
- Modify: `lib/core/database/finance_repository.dart` (`_loadPersistedState` tail; provider already has the notifier)
- Modify: `lib/features/navigation/main_shell.dart` (`didChangeAppLifecycleState`)

**Interfaces:**
- Consumes: `FinanceNotifier.processDueSipAutoPosts`.
- No new test — covered by Task 5's direct tests; this task's gate is `flutter analyze` + the full suite staying green + the manual check in Task 12.

- [ ] **Step 1: Kick the runner after the initial load** (`lib/core/database/finance_repository.dart`, end of `_loadPersistedState()`)

After the final `state = ...` assignment in `_loadPersistedState()`, add:
```dart
    unawaited(processDueSipAutoPosts());
```
> `unawaited` needs `import 'dart:async';` — already imported here (the provider uses `Timer`). Confirm.

- [ ] **Step 2: Kick it on resume** (`lib/features/navigation/main_shell.dart`, `didChangeAppLifecycleState`)

The method currently does:
```dart
    if (state == AppLifecycleState.resumed) {
      ref.read(financeNotifierProvider.notifier).refreshFromCloud();
      ref.read(notesProvider.notifier).refreshFromCloud();
    }
```
Change the finance line to:
```dart
      final finance = ref.read(financeNotifierProvider.notifier);
      finance.refreshFromCloud().then((_) => finance.processDueSipAutoPosts());
```
> If `refreshFromCloud()` returns `void` (not `Future`), instead call them sequentially:
> ```dart
> finance.refreshFromCloud();
> finance.processDueSipAutoPosts();
> ```
> Check its signature and pick the matching form.

- [ ] **Step 3: Analyze + full suite**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/core/database/finance_repository.dart lib/features/navigation/main_shell.dart
git commit -m "feat(sip): run SIP auto-post on load and on app resume"
```

---

## Task 7: Dashboard "Upcoming SIPs" tile

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/money_summary_card.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart`

**Interfaces:**
- Consumes: `FinanceState.totalMonthlySipAmount` (already exists).
- Produces: `MoneySummaryCard` gains a required `double upcomingSips`; the three-tile row becomes a 2×2 grid (Bank Balance / Card Due — Upcoming EMIs / Upcoming SIPs).

- [ ] **Step 1: Add the field + restructure the tiles** (`money_summary_card.dart`)

Add `final double upcomingSips;` after `upcomingEmis`, and `required this.upcomingSips,` in the constructor.

Replace the single `Row(children: [ _buildMetricCard('Bank Balance'...), _buildMetricCard('Card Due'...), _buildMetricCard('Upcoming EMIs'...) ])` with two rows:
```dart
          Row(
            children: [
              _buildMetricCard('Bank Balance', CurrencyFormatter.format(bankBalance),
                  LucideIcons.landmark, AppColors.accent),
              const SizedBox(width: 8),
              _buildMetricCard('Card Due', CurrencyFormatter.format(creditCardDue),
                  LucideIcons.creditCard, AppColors.creditCard),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMetricCard('Upcoming EMIs', CurrencyFormatter.format(upcomingEmis),
                  LucideIcons.clock, AppColors.loan),
              const SizedBox(width: 8),
              _buildMetricCard('Upcoming SIPs', CurrencyFormatter.format(upcomingSips),
                  LucideIcons.repeat, AppColors.transfer),
            ],
          ),
```
> `_buildMetricCard` already wraps its content in `Expanded` (it sits in a `Row` today). If it does **not**, wrap each call in `Expanded(child: ...)` so two-per-row lay out evenly. Verify by reading `_buildMetricCard`.

- [ ] **Step 2: Pass the value from the screen** (`dashboard_screen.dart`)

At **both** `MoneySummaryCard(...)` / `MoneySummaryCardData(...)` call sites (large-screen ~line 137, small-screen ~line 157), add:
```dart
                            upcomingSips: financeState.totalMonthlySipAmount,
```

- [ ] **Step 3: Analyze + widget test**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test test/widget_test.dart test/list_row_overflow_test.dart`
Expected: PASS (dashboard renders; no overflow).

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/
git commit -m "feat(sip): dashboard Upcoming SIPs tile"
```

---

## Task 8: Calendar consumes `upcomingObligations`

**Files:**
- Modify: `lib/features/recurring/presentation/calendar_screen.dart`

**Interfaces:**
- Consumes: `FinanceState.upcomingObligations(DateTime)`, `UpcomingObligation`, `ObligationKind`.
- Behaviour: dots, the "N payments due" chip, and the obligations list are derived from `upcomingObligations(<the month the calendar is showing>)` instead of `financeState.recurringPayments`. A row with `kind == sip` taps through to `/investments`; `kind == recurring` opens the existing edit sheet. The "+" FAB still creates a `RecurringPaymentModel` only.

- [ ] **Step 1: Read the screen** and identify: the focused/selected month variable, where `dueDays` / `incomeDays` / `upcoming` / `future` are built (around line 58–98), the dot builder, the chip text (line ~221), the list builder (line ~240–300), and the row `onTap` that calls `_showRecurringSheet`.

- [ ] **Step 2: Swap the data source**

Replace:
```dart
    final recurring = financeState.recurringPayments;
```
and the `dueDays` / `incomeDays` / `upcoming` / `future` derivations with:
```dart
    final obligations = financeState.upcomingObligations(_focusedMonth); // the month the grid shows
    final dueDays = <int>{
      for (final o in obligations)
        if (!o.isIncome && o.date.year == _focusedMonth.year && o.date.month == _focusedMonth.month)
          o.date.day,
    };
    final incomeDays = <int>{
      for (final o in obligations)
        if (o.isIncome && o.date.year == _focusedMonth.year && o.date.month == _focusedMonth.month)
          o.date.day,
    };
    final now = DateTime.now();
    final upcoming = obligations.where((o) => !o.date.isBefore(DateTime(now.year, now.month, now.day))).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
```
> Use whatever the screen's real focused-month field is called (it may be `_selectedMonth`, `_focused`, `_month`, or derived from a `DateTime _selectedDate`). Keep the existing empty-state / "future" fallback behaviour: if `upcoming` is empty, fall back to the full `obligations` list as the screen does today.

- [ ] **Step 3: Update the list rows + chip**

- Chip (line ~221): keep counting `dueDays` (now sourced from obligations).
- List item: bind to `UpcomingObligation`. Title = `o.title`; amount = `o.amount`; date = `o.date`; an income obligation keeps its existing "expected" styling if the screen has it.
- Row `onTap`:
```dart
  onTap: () {
    if (o.kind == ObligationKind.sip) {
      context.push('/investments');
    } else {
      final rp = financeState.recurringPayments.firstWhere((r) => r.id == o.sourceId);
      _showRecurringSheet(context, ref, financeState, existing: rp);
    }
  },
```
- The swipe-to-delete / long-press-delete on a row must be **disabled for `kind == sip`** (there is no recurring row to delete). Guard the `Dismissible` / `onLongPress` with `if (o.kind == ObligationKind.recurring)`.

- [ ] **Step 4: Analyze + navigation test**

Run: `flutter analyze`
Expected: clean.
Run: `flutter test test/navigation_back_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/recurring/presentation/calendar_screen.dart
git commit -m "feat(sip): show SIP occurrences in the Financial Calendar"
```

---

## Task 9: "Auto-invest on SIP day" switch — Add Investment modal

**Files:**
- Modify: `lib/features/investments/presentation/add_investment_modal.dart`

**Interfaces:**
- Consumes: `FinanceNotifier.addInvestment({..., bool autoInvestEnabled = false})` (Task 1).

- [ ] **Step 1: Add state + control** (`add_investment_modal.dart`)

Add `bool _autoInvest = false;` to the state class.

After the "SIP Day (1-28)" `TextField` (line ~167), add:
```dart
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-invest on SIP day'),
              subtitle: const Text('Post this SIP automatically each month'),
              value: _autoInvest,
              onChanged: (double.tryParse(_sipController.text.trim()) ?? 0) > 0
                  ? (v) => setState(() => _autoInvest = v)
                  : null, // disabled until a SIP amount is entered
            ),
```
> Use the actual controller name for the "Monthly SIP" field (read the file — it is near line 156–160; likely `_sipController` / `_monthlySipController`). Wire a `setState`/`onChanged` on that field if needed so the switch enables live.

- [ ] **Step 2: Pass it through** — in the `addInvestment(...)` call (line ~213), add:
```dart
            autoInvestEnabled: _autoInvest,
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/investments/presentation/add_investment_modal.dart
git commit -m "feat(sip): auto-invest toggle in Add Investment"
```

---

## Task 10: SIP day + auto-invest in the Investments edit sheet

**Files:**
- Modify: `lib/features/investments/presentation/investments_screen.dart`

**Interfaces:**
- Consumes: `FinanceNotifier.updateInvestment(id, {..., int? sipDay, bool? autoInvestEnabled})` (Task 1).

- [ ] **Step 1: Read the edit sheet** (`investments_screen.dart`) — find the "Update Value" / "Update Investment" modal builder and its controllers/`updateInvestment(...)` call. It currently edits name / invested / current / monthly SIP.

- [ ] **Step 2: Add a "SIP Day" number field** to that sheet, pre-filled from `investment.sipDay`, `keyboardType: TextInputType.number`, and a `SwitchListTile.adaptive` "Auto-invest on SIP day" pre-filled from `investment.autoInvestEnabled` (same enable rule: only when the monthly SIP field parses to > 0).

- [ ] **Step 3: Pass them to `updateInvestment`** in that sheet's save handler:
```dart
        sipDay: int.tryParse(sipDayController.text.trim()),
        autoInvestEnabled: autoInvest,
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/investments/presentation/investments_screen.dart
git commit -m "feat(sip): edit SIP day + auto-invest on an existing investment"
```

---

## Task 11: SIP debit account setting

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart`

**Interfaces:**
- Consumes: `financeNotifierProvider` → `state.sipDebitAccountId`, `state.accountsWithCalculatedBalances`, `notifier.setSipDebitAccount(String?)`.

- [ ] **Step 1: Read `settings_screen.dart`** — find the section that renders the emergency-buffer / currency settings and the pattern it uses (a `ListTile` opening a dialog, or an inline control).

- [ ] **Step 2: Add a "SIP debit account" row**

A `ListTile` (or the screen's equivalent) titled **"SIP debit account"**, subtitle = the selected account's name or *"Not set — auto-invest is paused"*. Tapping opens a picker (`showModalBottomSheet` / `showDialog` — match the screen's style) listing the active liquid accounts (`state.accountsWithCalculatedBalances.where((a) => a.isActive)`), plus a **"None"** entry. Selecting calls:
```dart
    ref.read(financeNotifierProvider.notifier).setSipDebitAccount(picked?.id);
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/presentation/settings_screen.dart
git commit -m "feat(sip): SIP debit account setting"
```

---

## Task 12: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: "No issues found!" (or only pre-existing, unrelated warnings — diff against `main`).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all pass, including `sip_schema_test`, `sip_reminders_test`, `upcoming_obligations_test`, `sip_auto_post_test`, `migration_check_test`, `card_reminders_test`, `crud_sweep_test`, `finance_engine_test`.

- [ ] **Step 3: Release build sanity**

Run: `flutter build apk --release`
Expected: builds (per `MEMORY.md`: universal APK, no `--split-per-abi`).

- [ ] **Step 4: Manual smoke (iOS simulator, demo account)** — per the spec's Section 6 manual list:
  1. Add a SIP fund ₹5,000, SIP Day = today or earlier, auto-invest ON.
  2. Settings → SIP debit account = a bank account.
  3. Relaunch → an "Auto SIP" ₹5,000 expense on that account dated the SIP day; portfolio +₹5,000; Dashboard "Upcoming SIPs" ₹5,000; Calendar dot + row on the SIP day.
  4. Relaunch again → no second post.
  5. Toggle auto-invest OFF, SIP day to the future, relaunch → no post; reminder wording is "SIP due", not "auto-invests".

- [ ] **Step 5: Commit any fixes, then the plan is done.**

```bash
git add -A
git commit -m "chore(sip): verification pass"
```

---

## Self-review notes (author)

- Spec Section 1 (schema) → Task 1. Section 2 (runner) → Tasks 5–6. Section 3 (reminders) → Task 3. Section 4 (calendar/dashboard/modal) → Tasks 7–11. Section 5 (edge cases) → covered by Task 5 tests + Task 1 (absent-column tolerance) + Task 8 (sip row can't be deleted). Section 6 (testing) → Tasks 1–5 tests + Task 12.
- `copyWith` cannot set `sipDebitAccountId` back to `null` through `?? this` — Task 2 Step 5 calls this out and requires a `clearSipDebitAccount` flag (or equivalent). Do not skip it.
- `updateInvestment` gains `sipDay` in Task 1 even though the runner only needs `lastAutoPostedMonth`, because Task 10's edit sheet needs it and splitting the signature change across tasks would churn the same lines twice.
- Every UI task (7–11) says "read the file first" because exact widget/controller names are not reproduced here; the data-layer interfaces they depend on are fully specified in Tasks 1–5.
