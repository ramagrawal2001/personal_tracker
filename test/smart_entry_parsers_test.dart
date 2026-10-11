import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/smart_entry/ai_transaction_service.dart';
import 'package:aspyric/core/services/smart_entry/bank_message_parser.dart';
import 'package:aspyric/core/services/smart_entry/entry_suggestions.dart';
import 'package:aspyric/core/services/smart_entry/receipt_parser.dart';
import 'package:aspyric/core/services/smart_entry/transaction_text_parser.dart';
import 'package:aspyric/core/services/merchant_categorizer.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FinanceNotifier n;
  late String hdfcId;
  late String sbiId;
  late String iciciCardId;
  late String hdfcDebitId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    n = createTestFinanceNotifier();
    await n.addAccount(name: 'HDFC Savings', type: AccountType.savingsAccount, bank: 'HDFC Bank', accountNumberLast4: '4321', openingBalance: 50000);
    await n.addAccount(name: 'SBI Salary', type: AccountType.savingsAccount, bank: 'SBI', accountNumberLast4: '9876', openingBalance: 10000);
    hdfcId = n.state.accounts.firstWhere((a) => a.name == 'HDFC Savings').id;
    sbiId = n.state.accounts.firstWhere((a) => a.name == 'SBI Salary').id;
    await n.addCard(
      cardType: CardType.credit, name: 'ICICI Amazon Pay', bank: 'ICICI Bank', last4: '1111',
      network: CardNetwork.visa, cardholderName: 'R', creditLimit: 100000, statementDay: 5, dueDay: 25,
    );
    await n.addCard(
      cardType: CardType.debit, name: 'HDFC Debit', bank: 'HDFC Bank', last4: '2222',
      network: CardNetwork.visa, cardholderName: 'R', linkedAccountId: hdfcId,
    );
    iciciCardId = n.state.creditCards.firstWhere((c) => c.last4 == '1111').id;
    hdfcDebitId = n.state.creditCards.firstWhere((c) => c.last4 == '2222').id;
  });

  final clock = DateTime(2026, 10, 11, 15); // a Sunday

  group('TransactionTextParser', () {
    TransactionTextParser p() => TransactionTextParser(n.state, clock: () => clock);

    test('amount + merchant + account + relative date', () {
      final r = p().parse('450 zomato hdfc yesterday');
      expect(r.amount, 450);
      expect(r.type, TransactionType.expense);
      expect(r.merchant, 'Zomato');
      expect(r.categoryId, 'cat_food');
      expect(r.accountId, hdfcId);
      expect(r.date, DateTime(2026, 10, 10));
    });

    test('k suffix, cash, category word', () {
      final r = p().parse('spent 2.5k on groceries cash');
      expect(r.amount, 2500);
      expect(r.payCardId, kCashPaySentinel);
      expect(r.categoryId, 'cat_groceries');
    });

    test('"cash" uses the Cash account when the user keeps one', () async {
      await n.addAccount(name: 'Wallet', type: AccountType.cash, openingBalance: 2000);
      final walletId = n.state.accounts.firstWhere((a) => a.name == 'Wallet').id;
      final r = TransactionTextParser(n.state, clock: () => clock).parse('120 chai cash');
      expect(r.accountId, walletId);
      expect(r.payCardId, isNull);
      final ai = AiTransactionService.resolve({'type': 'expense', 'amount': 120, 'pay_with': 'cash'}, n.state);
      expect(ai.accountId, walletId);
      expect(ai.payCardId, isNull);
    });

    test('income keywords', () {
      final r = p().parse('received 50000 salary sbi');
      expect(r.type, TransactionType.income);
      expect(r.amount, 50000);
      expect(r.accountId, sbiId);
      expect(r.categoryId, 'cat_salary');
      expect(r.payCardId, isNull);
    });

    test('spoken number words + weekday', () {
      final r = p().parse('two hundred fifty for petrol on friday');
      expect(r.amount, 250);
      expect(r.categoryId, 'cat_transport');
      expect(r.date, DateTime(2026, 10, 9));
    });

    test('credit card by name', () {
      final r = p().parse('1299 amazon icici card');
      expect(r.payCardId, iciciCardId);
      expect(r.merchant, 'Amazon');
    });

    test('debit card resolves to its linked account', () {
      final r = p().parse('300 dmart hdfc debit card');
      expect(r.payCardId, hdfcDebitId);
      expect(r.accountId, hdfcId);
    });

    test('merchant + notes split on "for"', () {
      final r = p().parse('500 to ramesh for dinner');
      expect(r.merchant, 'Ramesh');
      expect(r.notes, 'Dinner');
      expect(r.categoryId, 'cat_food');
    });

    test('explicit date', () {
      expect(p().parse('100 chai 5 oct').date, DateTime(2026, 10, 5));
      expect(p().parse('100 chai on 3rd').date, DateTime(2026, 10, 3));
    });
  });

  group('BankMessageParser', () {
    BankMessageParser p() => BankMessageParser(n.state);

    test('HDFC UPI debit SMS', () {
      final r = p().parse(
        'Sent Rs.450.00 From HDFC Bank A/C *4321 To SWIGGY On 10/10/26 Ref 628312345678 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808',
      )!;
      expect(r.amount, 450);
      expect(r.type, TransactionType.expense);
      expect(r.accountId, hdfcId);
      expect(r.merchant, 'Swiggy');
      expect(r.categoryId, 'cat_food');
      expect(r.reference, '628312345678');
      expect(r.date, DateTime(2026, 10, 10));
    });

    test('credit card spend SMS resolves the card', () {
      final r = p().parse(
        'INR 1,299.00 spent on ICICI Bank Card XX1111 on 09-Oct-26 at AMAZON PAY IN. Avl Limit: INR 98,701.00. If not you, call 1800 2662.',
      )!;
      expect(r.amount, 1299);
      expect(r.payCardId, iciciCardId);
      expect(r.merchant, 'Amazon Pay In');
      expect(r.categoryId, 'cat_shopping');
    });

    test('salary credit SMS', () {
      final r = p().parse(
        'Dear Customer, your A/c XX9876 is credited with Rs 85,000.00 on 01-10-2026 by NEFT from ACME TECHNOLOGIES PVT LTD. Avl Bal Rs 95,000.00 -SBI',
      )!;
      expect(r.type, TransactionType.income);
      expect(r.amount, 85000);
      expect(r.accountId, sbiId);
    });

    test('GPay notification text', () {
      final r = p().parse('You paid ₹120 to Chai Point')!;
      expect(r.amount, 120);
      expect(r.merchant, 'Chai Point');
      expect(r.type, TransactionType.expense);
    });

    test('UPI VPA becomes a readable merchant', () {
      final r = p().parse('Rs 89.00 debited from a/c **4321 on 11-10-26 to VPA zomato.order@hdfcbank (UPI Ref No 512345678901)')!;
      expect(r.merchant, 'Zomato Order');
      expect(r.reference, '512345678901');
    });

    test('rejects OTPs, promos, dues and failures', () {
      expect(p().parse('123456 is your OTP for txn of Rs 500 at Amazon. Do not share.'), isNull);
      expect(p().parse('Your ICICI card bill of Rs 12,000 is due on 25-Oct. Pay now.'), isNull);
      expect(p().parse('Txn of Rs 500 failed at Swiggy due to insufficient funds'), isNull);
      expect(p().parse('Congratulations! You are eligible for a pre-approved loan of Rs 5,00,000'), isNull);
      expect(p().parse('Hi, how are you?'), isNull);
    });

    test('looksTransactional pre-filter', () {
      expect(BankMessageParser.looksTransactional('Rs.450 debited from a/c'), isTrue);
      expect(BankMessageParser.looksTransactional('Meeting at 5'), isFalse);
    });
  });

  group('ReceiptParser', () {
    test('restaurant bill picks the grand total, not tax lines', () {
      final r = ReceiptParser(n.state).parse('''
BARBEQUE NATION
Tax Invoice
Date: 08/10/2026
Paneer Tikka 1 350.00
Butter Naan 4 240.00
Sub Total 590.00
CGST 2.5% 14.75
SGST 2.5% 14.75
Grand Total 619.50
Thank you''');
      expect(r.amount, 619.5);
      expect(r.merchant, 'Barbeque Nation');
      expect(r.date, DateTime(2026, 10, 8));
    });

    test('two-column OCR output (labels then numbers)', () {
      final r = ReceiptParser(n.state).parse('''
CAFE COFFEE DAY
Tax Invoice
Date: 09/10/2026
Cappuccino
Veg Sandwich
2
1
Sub Total
CGST 2.5%
SGST 2.5%
Grand Total
Paid by UPI
Thank you, visit again!
Time: 18:42
360.00
190.00
550.00
13.75
13.75
577.50''');
      expect(r.amount, 577.5);
      expect(r.merchant, 'Cafe Coffee Day');
      expect(r.categoryId, 'cat_food');
    });

    test('UPI success screenshot', () {
      final r = ReceiptParser(n.state).parse('''
Payment successful
₹450
Paid to
Swiggy
UPI transaction ID 512345678901''');
      expect(r.amount, 450);
      expect(r.merchant, 'Swiggy');
      expect(r.categoryId, 'cat_food');
    });
  });

  group('EntrySuggestions', () {
    test('remembers merchant habits and frequent combos', () async {
      for (var i = 0; i < 3; i++) {
        await n.addTransaction(
          accountId: hdfcId, type: TransactionType.expense, amount: 20, categoryId: 'cat_food',
          merchant: 'Chai Point', date: DateTime(2026, 10, 1 + i), isCashSpend: true,
        );
      }
      await n.addTransaction(
        accountId: hdfcId, type: TransactionType.expense, amount: 999, categoryId: 'cat_shopping',
        merchant: 'Myntra', date: DateTime(2026, 10, 5), creditCardId: iciciCardId,
      );
      final s = EntrySuggestions(n.state);
      final mem = s.forMerchant('chai point')!;
      expect(mem.categoryId, 'cat_food');
      expect(mem.payCardId, kCashPaySentinel);
      expect(s.forMerchant('Myntra')!.payCardId, iciciCardId);
      expect(s.matchMerchants('ch'), ['Chai Point']);
      final combos = s.frequentCombos();
      expect(combos.length, 1);
      expect(combos.single.merchant, 'Chai Point');
      expect(combos.single.lastAmount, 20);
      // learned category beats the built-in rules
      expect(s.categoryFor('Myntra'), 'cat_shopping');
    });

    test('lastOfType gives the latest habit', () async {
      await n.addTransaction(accountId: sbiId, type: TransactionType.expense, amount: 10, date: DateTime(2026, 10, 2));
      expect(EntrySuggestions(n.state).lastOfType(TransactionType.expense)!.accountId, sbiId);
    });
  });

  group('AI response mapping', () {
    test('extracts fenced JSON and maps names to ids', () {
      final j = AiTransactionService.extractJson('Sure!\n```json\n{"type":"expense","amount":"₹1,299","merchant":"Amazon","category":"Shopping","account":null,"pay_with":"ICICI Amazon Pay (credit card)","date":"2026-10-09","notes":null}\n```')!;
      final r = AiTransactionService.resolve(j, n.state);
      expect(r.amount, 1299);
      expect(r.categoryId, 'cat_shopping');
      expect(r.payCardId, iciciCardId);
      expect(r.date, DateTime(2026, 10, 9));
    });

    test('cash and income', () {
      final r = AiTransactionService.resolve({'type': 'income', 'amount': 500, 'category': 'Freelancing', 'pay_with': 'cash'}, n.state);
      expect(r.type, TransactionType.income);
      expect(r.categoryId, 'cat_freelance');
      expect(r.payCardId, isNull, reason: 'income never has a pay-with card');
    });
  });

  test('chat models ranked first, speech/guard models dropped', () {
    final r = AiTransactionService.rankChatModels([
      'allam-2-7b', 'canopylabs/orpheus-arabic-saudi', 'whisper-large-v3', 'meta-llama/llama-guard-4-12b',
      'llama-3.1-8b-instant', 'openai/gpt-oss-20b', 'openai/gpt-oss-120b', 'qwen/qwen3-32b',
    ]);
    expect(r.first, 'openai/gpt-oss-120b');
    expect(r, isNot(contains('whisper-large-v3')));
    expect(r, isNot(contains('canopylabs/orpheus-arabic-saudi')));
    expect(r, isNot(contains('meta-llama/llama-guard-4-12b')));
    expect(r.last, 'allam-2-7b');
  });

  test('MerchantCategorizer uses word boundaries', () {
    expect(MerchantCategorizer.categorize('Motorola store'), isNull);
    expect(MerchantCategorizer.categorize('OLA CABS ride')!.categoryId, 'cat_transport');
  });
}
