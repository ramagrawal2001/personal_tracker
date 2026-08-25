# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Aspyric** — a Flutter personal finance management app (package: `aspyric`). Targets Android, iOS, and other platforms.

## Commands

```bash
# Run the app
flutter run

# Run on specific device
flutter run -d android
flutter run -d ios

# Build
flutter build apk
flutter build ios

# Pub
flutter pub get
flutter pub upgrade

# Code generation (Drift ORM, etc.)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch

# Tests
flutter test
flutter test test/widget_test.dart   # single test file

# Lint
flutter analyze

# Generate launcher icons
dart run flutter_launcher_icons
```

## Architecture

The app uses **Riverpod** for state management and **go_router** for navigation.

### State Management

All app state lives in Riverpod `StateNotifier`s:

- `financeNotifierProvider` (`FinanceNotifier` / `FinanceState`) — the central store for all financial data: accounts, transactions, credit cards, loans, budgets, investments, goals, categories, recurring payments. All financial calculations (net worth, safe-to-spend, monthly income/expenses) are computed as getters on `FinanceState`.
- `authNotifierProvider` (`AuthNotifier` / `AuthState`) — authentication state, session persistence via `SharedPreferences`.
- `syncEngineProvider` — online/offline sync tracking.
- `themeProvider`, `localeProvider`, `userProfileProvider`, `notesProvider` — other app-level providers.

### Routing

`lib/core/router/app_router.dart` defines a `GoRouter` with:
- Public routes (no shell): `/splash`, `/login`, `/forgot-password`, `/privacy-policy`, `/terms`, `/admin`
- Shell routes (authenticated, wrapped in `BiometricGate` + `MainShell`): all finance and notes screens

### Navigation Shell

`lib/features/navigation/main_shell.dart` — `MainShell` wraps all authenticated routes. It provides:
- A **module switcher** tab bar at the top (Finance vs. Notes)
- A bottom nav bar (Dashboard, Transactions, Quick Add FAB, Accounts, More)
- A "More" bottom sheet grid for secondary modules (Cards, Loans, Budgets, Goals, Categories, Investments, Calendar, Reports, Net Worth, Analytics, Import, Settings)

### Data Layer

- **Models**: `lib/domain/models/models.dart` — plain Dart classes (no ORM). Key models: `AccountModel`, `TransactionModel`, `CardModel` (alias `CreditCardModel`), `LoanModel`, `BudgetModel`, `RecurringPaymentModel`, `InvestmentModel`, `GoalModel`, `CategoryModel`.
- **Enums**: `lib/core/constants/app_constants.dart` — `AccountType`, `TransactionType`, `PaymentFrequency`, `InvestmentType`.
- **Repository**: `lib/core/database/finance_repository.dart` — `FinanceNotifier` acts as the in-memory repository. All mutations go through its methods (`addTransaction`, `addAccount`, `addCard`, etc.). Account balances are dynamically calculated from the opening balance + all transaction history, never stored directly.
- **Drift** (SQLite ORM) is a dependency but the primary runtime store is the Riverpod in-memory `FinanceState`; Drift tables are defined in `lib/core/database/tables.dart`.

### Auth

`lib/features/auth/presentation/auth_repository.dart` — `AuthNotifier` handles:
- Supabase email/password auth (primary)
- OTP email verification via **Resend** API (`EmailOtpService` in `lib/core/services/email_otp_service.dart`)
- Session persistence via `SharedPreferences` (survives app restarts)
- Demo/test account bypass (no Supabase needed): `test@aspyric.app`, `demo@aspyric.app`, `admin@aspyric.app` — all use password `Aspyric@123`

### Services

| Service | Location | Purpose |
|---|---|---|
| `SupabaseService` | `lib/core/services/supabase_service.dart` | Supabase init + cloud sync |
| `EmailOtpService` | `lib/core/services/email_otp_service.dart` | OTP send/verify via Resend |
| `SyncEngineNotifier` | `lib/core/services/sync_engine.dart` | Offline queue flush |
| `NotificationService` | `lib/core/services/notification_service.dart` | Local push notifications |
| `BiometricService` | `lib/core/services/biometric_service.dart` | Fingerprint/Face ID |
| `BackupService` | `lib/core/services/backup_service.dart` | Data export/import |

### Theme & UI

- `lib/core/theme/app_colors.dart` — all color constants (`AppColors.*`)
- `lib/core/theme/app_theme.dart` — light/dark `ThemeData`
- `lib/core/theme/app_decorations.dart` — reusable `BoxDecoration` helpers
- `lib/core/widgets/` — shared widgets: `AppCard`, `SummaryCard`, `SectionHeader`, `EmptyState`, `AppScaffold`
- Icons: `lucide_icons` package + `LucideIcons.*` constants

### Localization

Supports English (`en`), Hindi (`hi`), and Marathi (`mr`). String files are manually maintained in `lib/core/l10n/`. Access via `AppLocalizations.of(context).someKey`. The `pubspec.yaml` has `generate: true` for ARB generation support.

### External Config

`lib/core/config/env_config.dart` — Supabase URL/keys and Resend API key are hardcoded here (not in `.env` files).

## Key Conventions

- **Account balance** is never stored directly — always computed as `openingBalance + income - expenses` across all transactions for that account (`FinanceState.accountsWithCalculatedBalances`).
- **Safe to Spend** = `totalLiquidBalance - upcomingPaymentsTotal - emergencyBuffer`.
- Feature screens live in `lib/features/<feature>/presentation/`. Modals are shown via static `.show(context)` methods.
- New features follow the `StateNotifier` + provider pattern; add state fields and mutator methods to `FinanceNotifier` / `FinanceState`.
- `CreditCardModel` is a typedef alias for `CardModel` (backward compat).
