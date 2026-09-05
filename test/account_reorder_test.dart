// Accounts reordering — regression lock for the new sortOrder field and
// FinanceNotifier.reorderAccounts (part of the `flutter test` suite).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FinanceNotifier finance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    finance = FinanceNotifier(db, autoLoad: false);
  });

  tearDown(() async {
    await db.close();
  });

  test('new accounts append to the end of the existing order', () async {
    await finance.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 1000);
    await finance.addAccount(name: 'ICICI', type: AccountType.savingsAccount, openingBalance: 2000);
    await finance.addAccount(name: 'Cash', type: AccountType.cash, openingBalance: 500);

    final byName = {for (final a in finance.state.accounts) a.name: a.sortOrder};
    expect(byName['HDFC'], 0);
    expect(byName['ICICI'], 1);
    expect(byName['Cash'], 2);
  });

  test('accountsWithCalculatedBalances follows sortOrder, not insertion order', () async {
    await finance.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 1000);
    await finance.addAccount(name: 'ICICI', type: AccountType.savingsAccount, openingBalance: 2000);
    await finance.addAccount(name: 'Cash', type: AccountType.cash, openingBalance: 500);

    // Untouched: sortOrder ties don't happen here (append always increments),
    // so the natural creation order is exactly what's expected before any
    // reorder — this just locks in that the getter actually sorts by it
    // rather than by list-append order.
    expect(finance.state.accountsWithCalculatedBalances.map((a) => a.name).toList(),
        ['HDFC', 'ICICI', 'Cash']);

    final ids = finance.state.accounts.map((a) => a.id).toList(); // [HDFC, ICICI, Cash]
    // Move Cash to the front.
    await finance.reorderAccounts([ids[2], ids[0], ids[1]]);

    expect(finance.state.accountsWithCalculatedBalances.map((a) => a.name).toList(),
        ['Cash', 'HDFC', 'ICICI']);
    // Calculated balances must still be correct after a reorder — it's a
    // display-order change only, never a balance mutation.
    final byName = {for (final a in finance.state.accountsWithCalculatedBalances) a.name: a.calculatedBalance};
    expect(byName['HDFC'], 1000);
    expect(byName['ICICI'], 2000);
    expect(byName['Cash'], 500);
  });

  test('reorderAccounts is a no-op when the order already matches', () async {
    await finance.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 1000);
    await finance.addAccount(name: 'ICICI', type: AccountType.savingsAccount, openingBalance: 2000);
    final before = finance.state.accounts.map((a) => a.updatedAt).toList();

    final ids = finance.state.accounts.map((a) => a.id).toList();
    await finance.reorderAccounts(ids); // already in this order

    final after = finance.state.accounts.map((a) => a.updatedAt).toList();
    expect(after, before, reason: 'nothing changed, so nothing should be rewritten');
  });
}
