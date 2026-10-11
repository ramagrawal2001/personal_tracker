import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FinanceNotifier n;
  late String acc;

  setUp(() async {
    // Auto-posting "enabled" since 1 Sep 2026 on this install.
    SharedPreferences.setMockInitialValues({
      kPrefRecurringAutoPostSince: DateTime(2026, 9, 1).millisecondsSinceEpoch,
    });
    n = createTestFinanceNotifier();
    await n.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 100000);
    acc = n.state.accounts.first.id;
  });

  Iterable auto() => n.state.transactions.where((t) => t.tags.contains('recurring-auto'));

  test('posts each due occurrence once and advances the due date', () async {
    await n.addRecurringPayment(
      title: 'Rent', amount: 15000, frequency: PaymentFrequency.monthly,
      nextDueDate: DateTime(2026, 9, 5), categoryId: 'cat_housing', accountId: acc, isAutoPay: true,
    );
    await n.processDueRecurringAutoPosts(DateTime(2026, 10, 11, 12));
    expect(auto().length, 2); // 5 Sep + 5 Oct
    expect(auto().every((t) => t.merchant == 'Rent' && t.amount == 15000 && t.type == TransactionType.expense), isTrue);
    expect(n.state.recurringPayments.first.nextDueDate, DateTime(2026, 11, 5));

    // Idempotent re-run.
    await n.processDueRecurringAutoPosts(DateTime(2026, 10, 11, 13));
    expect(auto().length, 2);
  });

  test('does not back-fill occurrences before auto-posting was switched on', () async {
    await n.addRecurringPayment(
      title: 'Netflix', amount: 649, frequency: PaymentFrequency.monthly,
      nextDueDate: DateTime(2026, 7, 20), accountId: acc, isAutoPay: true,
    );
    await n.processDueRecurringAutoPosts(DateTime(2026, 10, 11));
    // Jul 20 + Aug 20 are before "since" (1 Sep) → skipped; Sep 20 posted.
    expect(auto().map((t) => t.date), [DateTime(2026, 9, 20)]);
    expect(n.state.recurringPayments.first.nextDueDate, DateTime(2026, 10, 20));
  });

  test('ignores non-auto-pay, account-less, and future items', () async {
    await n.addRecurringPayment(title: 'Gym', amount: 1000, frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 10, 1), accountId: acc);
    await n.addRecurringPayment(title: 'Maid', amount: 3000, frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 10, 1), isAutoPay: true);
    await n.addRecurringPayment(title: 'Insurance', amount: 9000, frequency: PaymentFrequency.yearly, nextDueDate: DateTime(2026, 12, 1), accountId: acc, isAutoPay: true);
    await n.processDueRecurringAutoPosts(DateTime(2026, 10, 11));
    expect(auto(), isEmpty);
  });

  test('income recurring logs income; month-end days clamp', () async {
    await n.addRecurringPayment(
      title: 'Salary', amount: 80000, frequency: PaymentFrequency.monthly,
      nextDueDate: DateTime(2026, 9, 30), accountId: acc, isAutoPay: true, isIncome: true,
    );
    await n.processDueRecurringAutoPosts(DateTime(2026, 10, 11));
    expect(auto().single.type, TransactionType.income);
    expect(n.state.recurringPayments.first.nextDueDate, DateTime(2026, 10, 30));
  });
}
