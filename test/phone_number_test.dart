import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/phone_number.dart';

void main() {
  group('normalizePhone', () {
    test('strips what humans and contact pickers leave behind', () {
      expect(normalizePhone('333 123 4567'), '3331234567');
      expect(normalizePhone('06-1234567'), '061234567');
      expect(normalizePhone('(06) 1234567'), '061234567');
      expect(normalizePhone('06.123.4567'), '061234567');
    });

    test('keeps a leading international prefix', () {
      expect(normalizePhone('+39 333 1234567'), '+393331234567');
      expect(normalizePhone(' +39-333-1234567 '), '+393331234567');
    });

    test('drops a plus that is not leading', () {
      expect(normalizePhone('333+123'), '333123');
    });

    test('keeps the characters an extension may need', () {
      expect(normalizePhone('0612345#12'), '0612345#12');
      expect(normalizePhone('06123*45'), '06123*45');
    });

    test('handles an already clean number unchanged', () {
      expect(normalizePhone('3331234567'), '3331234567');
    });
  });

  group('isDialablePhone', () {
    test('accepts real numbers, Italian and international', () {
      expect(isDialablePhone('3331234567'), isTrue);
      expect(isDialablePhone('+39 333 1234567'), isTrue);
      expect(isDialablePhone('06 1234567'), isTrue);
      // Short internal extensions are legitimate.
      expect(isDialablePhone('112'), isTrue);
    });

    test('rejects empty or junk input', () {
      expect(isDialablePhone(''), isFalse);
      expect(isDialablePhone('   '), isFalse);
      expect(isDialablePhone('abc'), isFalse);
      expect(isDialablePhone('12'), isFalse);
      expect(isDialablePhone('+'), isFalse);
    });
  });

  group('telUri', () {
    test('builds a tel URI from the normalised number', () {
      // A literal space or bracket is not valid tel: syntax and some dialers
      // silently drop the rest of the number.
      expect(telUri('333 123 4567').toString(), 'tel:3331234567');
      expect(telUri('+39 333 1234567').toString(), 'tel:+393331234567');
      expect(telUri('(06) 1234567').toString(), 'tel:061234567');
    });
  });

  group('formatPhoneForDisplay', () {
    test('shows the number the way the user wrote it', () {
      expect(formatPhoneForDisplay('+39 333 1234567'), '+39 333 1234567');
      expect(formatPhoneForDisplay('  06-1234567 '), '06-1234567');
    });
  });
}
