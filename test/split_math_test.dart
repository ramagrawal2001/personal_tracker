// Split math (equal / custom / ratio / percentage) — regression lock for
// resolveSplitShares (part of the `flutter test` suite).

import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:aspyric/features/splits/presentation/split_expense_modal.dart';

void main() {
  group('resolveSplitShares', () {
    test('equal: splits evenly among participants + payer, rounded to cents', () {
      final shares = resolveSplitShares(
        mode: SplitMode.equal,
        totalAmount: 100,
        participantIds: ['rahul', 'priya'],
        participantInputs: const {},
      );
      expect(shares, isNotNull);
      // 100 / 3 = 33.333... -> 33.33 each; payer's implied share (100 - 66.66)
      // absorbs the rounding remainder, checked by the caller, not here.
      expect(shares!['rahul'], closeTo(33.33, 0.001));
      expect(shares['priya'], closeTo(33.33, 0.001));
    });

    test('custom: each participant gets exactly what was entered', () {
      final shares = resolveSplitShares(
        mode: SplitMode.custom,
        totalAmount: 100,
        participantIds: ['rahul', 'priya'],
        participantInputs: const {'rahul': 30, 'priya': 20},
      );
      expect(shares, {'rahul': 30.0, 'priya': 20.0});
    });

    test('custom: rejected when shares exceed the total', () {
      final shares = resolveSplitShares(
        mode: SplitMode.custom,
        totalAmount: 100,
        participantIds: ['rahul'],
        participantInputs: const {'rahul': 150},
      );
      expect(shares, isNull);
    });

    test('ratio: proportional to each person\'s ratio, payer included', () {
      // payer:2, rahul:1, priya:1 -> total ratio 4 -> rahul/priya get 1/4 each
      final shares = resolveSplitShares(
        mode: SplitMode.ratio,
        totalAmount: 400,
        participantIds: ['rahul', 'priya'],
        participantInputs: const {'rahul': 1, 'priya': 1},
        payerInput: 2,
      );
      expect(shares!['rahul'], 100.0);
      expect(shares['priya'], 100.0);
      // payer's implied share = 400 - 200 = 200, i.e. half — matches ratio 2/4.
    });

    test('ratio: rejected when every ratio (including payer) is zero', () {
      final shares = resolveSplitShares(
        mode: SplitMode.ratio,
        totalAmount: 100,
        participantIds: ['rahul'],
        participantInputs: const {'rahul': 0},
        payerInput: 0,
      );
      expect(shares, isNull);
    });

    test('percentage: proportional to each person\'s %, must total ~100 with payer', () {
      final shares = resolveSplitShares(
        mode: SplitMode.percentage,
        totalAmount: 200,
        participantIds: ['rahul', 'priya'],
        participantInputs: const {'rahul': 25, 'priya': 25},
        payerInput: 50,
      );
      expect(shares!['rahul'], 50.0);
      expect(shares['priya'], 50.0);
    });

    test('percentage: rejected when the total (with payer) isn\'t ~100', () {
      final shares = resolveSplitShares(
        mode: SplitMode.percentage,
        totalAmount: 200,
        participantIds: ['rahul'],
        participantInputs: const {'rahul': 25},
        payerInput: 50, // sums to 75, not 100
      );
      expect(shares, isNull);
    });

    test('no participants selected is always rejected', () {
      final shares = resolveSplitShares(
        mode: SplitMode.equal,
        totalAmount: 100,
        participantIds: const [],
        participantInputs: const {},
      );
      expect(shares, isNull);
    });
  });
}
