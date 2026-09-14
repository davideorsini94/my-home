import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/money_format_it.dart';

void main() {
  group('formatEuro', () {
    test('renders an unrecorded cost as N.D.', () {
      expect(formatEuro(null), 'N.D.');
    });

    test('always shows two decimals', () {
      expect(formatEuro(0), '€ 0,00');
      expect(formatEuro(5), '€ 0,05');
      expect(formatEuro(50), '€ 0,50');
      expect(formatEuro(12000), '€ 120,00');
    });

    test('groups thousands with dots, Italian style', () {
      expect(formatEuro(123456), '€ 1.234,56');
      expect(formatEuro(100000000), '€ 1.000.000,00');
      expect(formatEuro(99999), '€ 999,99');
    });

    test('handles a negative amount without mangling the sign', () {
      expect(formatEuro(-12000), '-€ 120,00');
    });
  });

  group('parseEuroCents', () {
    test('treats an empty field and N.D. as no cost', () {
      expect(parseEuroCents(''), isNull);
      expect(parseEuroCents('   '), isNull);
      expect(parseEuroCents('N.D.'), isNull);
      expect(parseEuroCents('n.d.'), isNull);
      expect(parseEuroCents('ND'), isNull);
    });

    test('accepts plain amounts', () {
      expect(parseEuroCents('120'), 12000);
      expect(parseEuroCents('0'), 0);
      expect(parseEuroCents('1234'), 123400);
    });

    test('accepts either decimal separator', () {
      expect(parseEuroCents('120,50'), 12050);
      expect(parseEuroCents('120.50'), 12050);
      expect(parseEuroCents('120,5'), 12050);
    });

    test('resolves both separators by taking the last as the decimal', () {
      // Italian and English groupings are mutually ambiguous; the position of
      // the last separator settles it without guessing a locale.
      expect(parseEuroCents('1.234,56'), 123456);
      expect(parseEuroCents('1,234.56'), 123456);
    });

    test('reads three trailing digits as a thousands group, not decimals', () {
      expect(parseEuroCents('1.234'), 123400);
      expect(parseEuroCents('1,234'), 123400);
      // The rule is applied consistently, so "120,505" is 120505 euro and not
      // a mistyped 120,50. Nothing is silently wrong: the field echoes the
      // parsed amount back formatted, so an unintended reading is visible
      // before saving.
      expect(parseEuroCents('120,505'), 12050500);
    });

    test('ignores the euro sign and spaces', () {
      expect(parseEuroCents('€ 120,00'), 12000);
      expect(parseEuroCents(' 120 '), 12000);
    });

    test('rejects anything that is not an amount', () {
      expect(() => parseEuroCents('abc'), throwsFormatException);
      expect(() => parseEuroCents('12a'), throwsFormatException);
      expect(() => parseEuroCents('-120'), throwsFormatException);
      expect(() => parseEuroCents(','), throwsFormatException);
    });
  });

  group('tryParseEuroCents', () {
    test('separates "no cost" from "not a number"', () {
      // Both would be a bare null, which is why this returns a record.
      expect(tryParseEuroCents(''), (valid: true, cents: null));
      expect(tryParseEuroCents('120'), (valid: true, cents: 12000));
      expect(tryParseEuroCents('abc'), (valid: false, cents: null));
    });
  });

  group('round trip', () {
    test('formatting then editing then parsing preserves the amount', () {
      for (final cents in [0, 5, 50, 12000, 123456, 100000000]) {
        expect(parseEuroCents(euroEditingValue(cents)), cents);
      }
    });

    test('the editing value omits pointless decimals', () {
      expect(euroEditingValue(null), '');
      expect(euroEditingValue(12000), '120');
      expect(euroEditingValue(12050), '120,50');
      expect(euroEditingValue(5), '0,05');
    });
  });
}
