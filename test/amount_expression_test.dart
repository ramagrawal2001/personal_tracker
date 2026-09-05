// Amount field quick-math ("100/3" -> 33.33) — regression lock (part of the
// `flutter test` suite).

import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/features/transactions/presentation/quick_add_modal.dart';

void main() {
  group('parseAmountExpression', () {
    test('plain numbers still parse exactly as before', () {
      expect(parseAmountExpression('120'), 120);
      expect(parseAmountExpression('120.5'), 120.5);
      expect(parseAmountExpression('  99  '), 99);
    });

    test('single binary expressions evaluate', () {
      expect(parseAmountExpression('100/3'), closeTo(33.3333, 0.0001));
      expect(parseAmountExpression('45+10.5'), 55.5);
      expect(parseAmountExpression('500-125'), 375);
      expect(parseAmountExpression('20*3'), 60);
      expect(parseAmountExpression('20x3'), 60, reason: 'x as a multiply shorthand');
      expect(parseAmountExpression('20×3'), 60, reason: 'unicode multiplication sign');
    });

    test('tolerates spacing around the operator', () {
      expect(parseAmountExpression('100 / 3'), closeTo(33.3333, 0.0001));
      expect(parseAmountExpression('100/ 3'), closeTo(33.3333, 0.0001));
    });

    test('division by zero is invalid, not infinity', () {
      expect(parseAmountExpression('100/0'), isNull);
    });

    test('only a single operator level is supported — chains are rejected', () {
      expect(parseAmountExpression('100/3/2'), isNull);
      expect(parseAmountExpression('10+20+30'), isNull);
    });

    test('garbage and empty input are rejected', () {
      expect(parseAmountExpression(''), isNull);
      expect(parseAmountExpression('abc'), isNull);
      expect(parseAmountExpression('100/'), isNull);
      expect(parseAmountExpression('/100'), isNull);
    });
  });
}
