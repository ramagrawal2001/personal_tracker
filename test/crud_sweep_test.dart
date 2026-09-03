// CRUD sweep — deterministic regression lock (part of the `flutter test` suite).
//
// Exercises the create → edit → delete round-trip for every core module
// through the real repository layer (`FinanceNotifier` + `NotesNotifier`),
// asserting that state, the reactive lists AND the derived getters
// (calculated balances, transfer recompute, budget spend, goal funds,
// credit-card outstanding delta on edit) all stay correct.
//
// The full UI-driven version (modals / sheets / dialogs against the real
// `AspyricApp`) lives in integration_test/crud_sweep_test.dart and runs on a
// device: `flutter test integration_test/crud_sweep_test.dart -d chrome`.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/providers/notes_provider.dart';
import 'package:aspyric/domain/models/note_model.dart';

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
    // Let the notifier's fire-and-forget write-through drain before the
    // in-memory DB is torn down, so the log stays clean.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await db.close();
  });

  group('Accounts CRUD', () {
    test('create → edit → delete, calculated balance follows', () {
      finance.addAccount(
          name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 1000);
      var acc = finance.state.accounts.single;
      expect(acc.name, 'HDFC');
      expect(
          finance.state.accountsWithCalculatedBalances.single.calculatedBalance,
          1000);

      finance.updateAccount(acc.id, name: 'HDFC Salary', openingBalance: 2500);
      acc = finance.state.accounts.single;
      expect(acc.name, 'HDFC Salary');
      expect(
          finance.state.accountsWithCalculatedBalances.single.calculatedBalance,
          2500);

      finance.deleteAccount(acc.id);
      expect(finance.state.accounts, isEmpty);
    });
  });

  group('Categories CRUD', () {
    test('create → edit → delete on top of the defaults', () {
      final baseline = finance.state.categories.length;
      finance.addCategory(name: 'Subscriptions', type: 'expense', icon: 'tag');
      final cat =
          finance.state.categories.firstWhere((c) => c.name == 'Subscriptions');
      expect(finance.state.categories.length, baseline + 1);

      finance.updateCategory(cat.id, name: 'Streaming', icon: 'tv');
      final edited = finance.state.categories.firstWhere((c) => c.id == cat.id);
      expect(edited.name, 'Streaming');
      expect(edited.icon, 'tv');

      finance.deleteCategory(cat.id);
      expect(finance.state.categories.any((c) => c.id == cat.id), isFalse);
      expect(finance.state.categories.length, baseline);
    });
  });

  group('Transactions CRUD', () {
    test('expense: create → edit amount → delete, monthly totals follow', () {
      finance.addAccount(
          name: 'Cash', type: AccountType.cash, openingBalance: 5000);
      final acc = finance.state.accounts.single.id;

      finance.addTransaction(
        accountId: acc,
        type: TransactionType.expense,
        amount: 750,
        categoryId: 'cat_food',
        merchant: 'Store',
        date: DateTime.now(),
      );
      var tx = finance.state.transactions.single;
      expect(finance.state.monthlyExpenses, 750);
      expect(
          finance.state.accountsWithCalculatedBalances.single.calculatedBalance,
          5000 - 750);

      finance.updateTransaction(tx.id, amount: 999, merchant: 'Store B');
      tx = finance.state.transactions.single;
      expect(tx.amount, 999);
      expect(tx.merchant, 'Store B');
      expect(finance.state.monthlyExpenses, 999);
      expect(
          finance.state.accountsWithCalculatedBalances.single.calculatedBalance,
          5000 - 999);

      finance.deleteTransaction(tx.id);
      expect(finance.state.transactions, isEmpty);
      expect(finance.state.monthlyExpenses, 0);
      expect(
          finance.state.accountsWithCalculatedBalances.single.calculatedBalance,
          5000);
    });

    test('transfer: moves money between two accounts and reverses on delete',
        () {
      finance.addAccount(
          name: 'A', type: AccountType.savingsAccount, openingBalance: 10000);
      finance.addAccount(
          name: 'B', type: AccountType.savingsAccount, openingBalance: 2000);
      final a = finance.state.accounts.firstWhere((x) => x.name == 'A').id;
      final b = finance.state.accounts.firstWhere((x) => x.name == 'B').id;

      finance.addTransaction(
        accountId: a,
        toAccountId: b,
        type: TransactionType.transfer,
        amount: 3000,
        date: DateTime.now(),
      );
      List<double> bal() => finance.state.accountsWithCalculatedBalances
          .map((x) => x.calculatedBalance)
          .toList();
      expect(
          finance.state.accountsWithCalculatedBalances
              .firstWhere((x) => x.id == a)
              .calculatedBalance,
          10000 - 3000);
      expect(
          finance.state.accountsWithCalculatedBalances
              .firstWhere((x) => x.id == b)
              .calculatedBalance,
          2000 + 3000);
      expect(bal().reduce((x, y) => x + y), 12000); // conserved

      finance.deleteTransaction(finance.state.transactions.single.id);
      expect(
          finance.state.accountsWithCalculatedBalances
              .firstWhere((x) => x.id == a)
              .calculatedBalance,
          10000);
      expect(
          finance.state.accountsWithCalculatedBalances
              .firstWhere((x) => x.id == b)
              .calculatedBalance,
          2000);
    });
  });

  group('Credit cards CRUD', () {
    test('create → edit → delete; expense edit adjusts outstanding by delta',
        () {
      finance.addCreditCard(
          name: 'ICICI',
          bank: 'ICICI',
          last4: '4417',
          creditLimit: 100000,
          statementDay: 3,
          dueDay: 20);
      var card = finance.state.creditCards.single;
      expect(card.currentOutstanding, 0);

      // spend on the card
      finance.addTransaction(
        accountId: 'n/a',
        type: TransactionType.expense,
        amount: 2000,
        date: DateTime.now(),
        creditCardId: card.id,
      );
      card = finance.state.creditCards.single;
      expect(card.currentOutstanding, 2000);

      // edit that charge up by 500 → outstanding tracks the delta
      final tx = finance.state.transactions.single;
      finance.updateTransaction(tx.id, amount: 2500);
      expect(finance.state.creditCards.single.currentOutstanding, 2500);

      // deleting the charge must reverse the outstanding it added
      finance.deleteTransaction(tx.id);
      expect(finance.state.creditCards.single.currentOutstanding, 0);

      finance.updateCard(card.id, name: 'ICICI Amazon Pay', creditLimit: 150000);
      card = finance.state.creditCards.single;
      expect(card.name, 'ICICI Amazon Pay');
      expect(card.creditLimit, 150000);

      finance.deleteCard(card.id);
      expect(finance.state.creditCards, isEmpty);
    });
  });

  group('Loans CRUD', () {
    test('create → edit → delete; EMI payment reduces outstanding & tenure', () {
      finance.addLoan(
        name: 'Car Loan',
        provider: 'Kotak',
        principalAmount: 500000,
        interestRate: 9,
        monthlyEmi: 10000,
        dueDay: 5,
        tenureMonths: 60,
      );
      var loan = finance.state.loans.single;
      expect(loan.outstandingAmount, 500000);
      expect(loan.remainingTenureMonths, 60);

      finance.addTransaction(
        accountId: 'n/a',
        type: TransactionType.loanPayment,
        amount: 10000,
        date: DateTime.now(),
        loanId: loan.id,
      );
      loan = finance.state.loans.single;
      expect(loan.outstandingAmount, 490000);
      expect(loan.remainingTenureMonths, 59);

      // deleting the EMI payment restores outstanding and tenure
      finance.deleteTransaction(finance.state.transactions.single.id);
      loan = finance.state.loans.single;
      expect(loan.outstandingAmount, 500000);
      expect(loan.remainingTenureMonths, 60);

      finance.updateLoan(loan.id, name: 'Car Loan (refi)', monthlyEmi: 9000);
      loan = finance.state.loans.single;
      expect(loan.name, 'Car Loan (refi)');
      expect(loan.monthlyEmi, 9000);

      finance.deleteLoan(loan.id);
      expect(finance.state.loans, isEmpty);
    });
  });

  group('Budgets CRUD', () {
    test('create → edit limit → delete; spend is recomputed from transactions',
        () {
      finance.addAccount(
          name: 'Cash', type: AccountType.cash, openingBalance: 100000);
      final acc = finance.state.accounts.single.id;
      finance.addBudget(categoryId: 'cat_food', monthlyLimit: 20000);
      var budget = finance.state.budgetsWithCalculatedSpend.single;
      expect(budget.monthlyLimit, 20000);
      expect(budget.spentAmount, 0);

      finance.addTransaction(
        accountId: acc,
        type: TransactionType.expense,
        amount: 3500,
        categoryId: 'cat_food',
        date: DateTime.now(),
      );
      expect(finance.state.budgetsWithCalculatedSpend.single.spentAmount, 3500);

      finance.updateBudget(finance.state.budgets.single.id, limitAmount: 25000);
      expect(finance.state.budgetsWithCalculatedSpend.single.monthlyLimit,
          25000);

      finance.deleteBudget(finance.state.budgets.single.id);
      expect(finance.state.budgets, isEmpty);
    });
  });

  group('Recurring payments CRUD', () {
    test('create → edit → delete; feeds upcoming obligations', () {
      finance.addRecurringPayment(
        title: 'Netflix',
        amount: 649,
        frequency: PaymentFrequency.monthly,
        nextDueDate: DateTime.now().add(const Duration(days: 5)),
      );
      var p = finance.state.recurringPayments.single;
      expect(p.title, 'Netflix');
      expect(finance.state.upcomingPaymentsTotal, greaterThan(0));

      finance.updateRecurringPayment(p.id,
          title: 'Netflix Premium',
          amount: 799,
          frequency: PaymentFrequency.yearly);
      p = finance.state.recurringPayments.single;
      expect(p.title, 'Netflix Premium');
      expect(p.amount, 799);
      expect(p.frequency, PaymentFrequency.yearly);

      finance.deleteRecurringPayment(p.id);
      expect(finance.state.recurringPayments, isEmpty);
    });
  });

  group('Investments CRUD', () {
    test('create → edit → delete; portfolio totals follow', () {
      finance.addInvestment(
        name: 'Nifty 50',
        type: InvestmentType.mutualFundSip,
        investedAmount: 300000,
        currentValue: 360000,
        monthlySipAmount: 15000,
      );
      var inv = finance.state.investments.single;
      expect(finance.state.totalInvestmentCurrentValue, 360000);
      expect(finance.state.totalMonthlySipAmount, 15000);

      // a SIP contribution transaction bumps invested + current value…
      finance.addTransaction(
        accountId: 'n/a',
        type: TransactionType.investment,
        amount: 15000,
        date: DateTime.now(),
        investmentId: inv.id,
      );
      expect(finance.state.investments.single.investedAmount, 315000);
      // …and deleting it reverses both
      finance.deleteTransaction(finance.state.transactions.single.id);
      expect(finance.state.investments.single.investedAmount, 300000);
      expect(finance.state.investments.single.currentValue, 360000);

      finance.updateInvestment(inv.id,
          name: 'Nifty 50 Index', currentValue: 375000, monthlySipAmount: 20000);
      inv = finance.state.investments.single;
      expect(inv.name, 'Nifty 50 Index');
      expect(finance.state.totalInvestmentCurrentValue, 375000);
      expect(finance.state.totalMonthlySipAmount, 20000);

      finance.deleteInvestment(inv.id);
      expect(finance.state.investments, isEmpty);
      expect(finance.state.totalInvestmentCurrentValue, 0);
    });
  });

  group('Goals CRUD', () {
    test('create → add funds → edit → delete', () {
      finance.addGoal(
        name: 'Japan Trip',
        targetAmount: 400000,
        currentSavedAmount: 100000,
        targetDate: DateTime.now().add(const Duration(days: 300)),
      );
      var goal = finance.state.goals.single;
      expect(goal.currentSavedAmount, 100000);

      finance.addFundsToGoal(goal.id, 25000);
      expect(finance.state.goals.single.currentSavedAmount, 125000);

      finance.updateGoal(goal.id, name: 'Japan 2027', targetAmount: 450000);
      goal = finance.state.goals.single;
      expect(goal.name, 'Japan 2027');
      expect(goal.targetAmount, 450000);
      expect(goal.currentSavedAmount, 125000); // untouched by the edit

      finance.deleteGoal(goal.id);
      expect(finance.state.goals, isEmpty);
    });
  });

  group('Notes CRUD', () {
    test('text note: create → edit → pin → archive → delete', () {
      final notes = NotesNotifier(db);
      var note = notes.createNote().copyWith(
            title: 'Groceries',
            body: 'milk, eggs',
          );
      notes.saveNote(note);
      expect(notes.state.notes.single.title, 'Groceries');

      note = notes.state.notes.single.copyWith(body: 'milk, eggs, bread');
      notes.saveNote(note);
      expect(notes.state.notes.single.body, 'milk, eggs, bread');

      notes.togglePin(note.id);
      expect(notes.state.pinned.single.id, note.id);

      notes.toggleArchive(note.id);
      expect(notes.state.archived.single.id, note.id);
      expect(notes.state.pinned, isEmpty); // archiving clears pin

      notes.toggleArchive(note.id);
      expect(notes.state.archived, isEmpty);

      notes.deleteNote(note.id);
      expect(notes.state.notes, isEmpty);
    });

    test('checklist note: create with items → edit item → delete', () {
      final notes = NotesNotifier(db);
      final note = notes.createNote().copyWith(
        isChecklist: true,
        title: 'Move-in checklist',
        checklistItems: const [
          NoteChecklistItem(id: 'i1', text: 'Electricity'),
          NoteChecklistItem(id: 'i2', text: 'Internet'),
        ],
      );
      notes.saveNote(note);
      final saved = notes.state.notes.single;
      expect(saved.isChecklist, isTrue);
      expect(saved.checklistItems.length, 2);

      notes.saveNote(saved.copyWith(checklistItems: [
        saved.checklistItems[0].copyWith(isChecked: true),
        saved.checklistItems[1],
      ]));
      expect(notes.state.notes.single.checklistItems[0].isChecked, isTrue);

      notes.deleteNote(saved.id);
      expect(notes.state.notes, isEmpty);
    });
  });

  group('Settings persistence', () {
    test('currency symbol, emergency buffer and toggles round-trip on state',
        () {
      finance.setCurrencySymbol(r'$');
      expect(finance.state.currencySymbol, r'$');

      finance.setEmergencyBuffer(50000);
      expect(finance.state.emergencyBuffer, 50000);

      finance.toggleRoundUp(true);
      finance.toggleAutoBackup(true);
      finance.toggleBiometric(true);
      expect(finance.state.isRoundUpEnabled, isTrue);
      expect(finance.state.isAutoBackupEnabled, isTrue);
      expect(finance.state.isBiometricEnabled, isTrue);
    });
  });
}
