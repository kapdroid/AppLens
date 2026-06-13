import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

FlagConstraint _c(String input) => FlagConstraint.parse(input);

void main() {
  group('FlagConstraint.parse', () {
    test('booleans', () {
      expect(_c('true'), isA<BoolConstraint>());
      expect((_c('false') as BoolConstraint).value, isFalse);
    });

    test('integer comparisons map to ranges', () {
      final gt = _c('>0') as IntRangeConstraint;
      expect(gt.low, 1);
      expect(gt.high, isNull);

      final le = _c('<=2') as IntRangeConstraint;
      expect(le.low, isNull);
      expect(le.high, 2);
    });

    test('a bare integer is an exact range', () {
      final eq = _c('3') as IntRangeConstraint;
      expect(eq.low, 3);
      expect(eq.high, 3);
    });

    test('any other literal is an exact match', () {
      expect(_c('ready'), isA<ExactConstraint>());
    });

    test('the raw spelling is preserved for round-tripping', () {
      expect(_c('>0').raw, '>0');
    });
  });

  group('contradicts (joint satisfiability on the same flag)', () {
    test('>0 and ==0 cannot both hold', () {
      expect(_c('>0').contradicts(_c('==0')), isTrue);
      expect(_c('==0').contradicts(_c('>0')), isTrue);
    });

    test('>0 and >=3 overlap', () {
      expect(_c('>0').contradicts(_c('>=3')), isFalse);
    });

    test('<0 and >0 are disjoint', () {
      expect(_c('<0').contradicts(_c('>0')), isTrue);
    });

    test('booleans contradict only when different', () {
      expect(_c('true').contradicts(_c('false')), isTrue);
      expect(_c('true').contradicts(_c('true')), isFalse);
    });

    test('different kinds cannot both hold', () {
      expect(_c('>0').contradicts(_c('ready')), isTrue);
      expect(_c('true').contradicts(_c('>0')), isTrue);
    });

    test('equal exact literals agree', () {
      expect(_c('ready').contradicts(_c('ready')), isFalse);
    });
  });

  group('accepts (runtime match against an observed value)', () {
    test('integer range accepts in-range values only', () {
      expect(_c('>0').accepts('3'), isTrue);
      expect(_c('>0').accepts('0'), isFalse);
      expect(_c('<=2').accepts('2'), isTrue);
      expect(_c('<=2').accepts('3'), isFalse);
      expect(_c('>0').accepts('notanumber'), isFalse);
    });

    test('booleans accept only their matching literal', () {
      expect(_c('true').accepts('true'), isTrue);
      expect(_c('true').accepts('false'), isFalse);
      expect(_c('false').accepts('nope'), isFalse);
    });

    test('exact accepts the same literal only', () {
      expect(_c('ready').accepts('ready'), isTrue);
      expect(_c('ready').accepts('pending'), isFalse);
    });
  });
}
