/// Italian euro formatting and parsing, written out rather than pulled from
/// `intl` so the app carries no locale-data initialisation and the strings stay
/// predictable in tests — the same reason `date_format_it.dart` exists.
///
/// Money is always cents in an `int`. A double would eventually turn €120.10
/// into €120.09999999999999.
library;

const String unknownCostLabel = 'N.D.';

/// "€ 1.234,56", or "N.D." when the cost was never recorded.
String formatEuro(int? cents) {
  if (cents == null) return unknownCostLabel;
  final negative = cents < 0;
  final abs = cents.abs();
  final units = abs ~/ 100;
  final decimals = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}€ ${_groupThousands(units)},$decimals';
}

/// "1234567" -> "1.234.567"
String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Parses a typed amount into cents.
///
/// Returns null for an empty field or an explicit "N.D." — both mean "no cost
/// recorded", which is a legitimate value and not an error.
///
/// Accepts what an Italian keyboard actually produces: `120`, `120,5`,
/// `120,50`, `120.50`, `1.234,56` and `1,234.56`. When both separators appear
/// the LAST one is the decimal separator, which resolves the ambiguity between
/// Italian and English conventions without guessing.
///
/// Throws [FormatException] on anything else, negatives included: a negative
/// maintenance cost is a typo, not an intention.
int? parseEuroCents(String raw) {
  final text = raw.trim().replaceAll('€', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  if (text.toUpperCase().replaceAll('.', '') == 'ND') return null;

  if (!RegExp(r'^[0-9.,]+$').hasMatch(text)) {
    throw FormatException('Importo non valido', raw);
  }

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  final decimalAt = lastComma > lastDot ? lastComma : lastDot;

  String unitsPart;
  String decimalsPart;
  if (decimalAt < 0) {
    unitsPart = text;
    decimalsPart = '00';
  } else {
    final tail = text.substring(decimalAt + 1);
    // Three digits after the last separator means it was a thousands grouping,
    // not a decimal point: "1.234" is one thousand two hundred thirty-four.
    if (tail.length == 3 && text.length > 4) {
      unitsPart = text;
      decimalsPart = '00';
    } else {
      unitsPart = text.substring(0, decimalAt);
      decimalsPart = tail;
    }
  }

  final units = unitsPart.replaceAll('.', '').replaceAll(',', '');
  if (units.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(units)) {
    throw FormatException('Importo non valido', raw);
  }
  if (decimalsPart.isEmpty || !RegExp(r'^[0-9]{1,2}$').hasMatch(decimalsPart)) {
    throw FormatException('Importo non valido', raw);
  }

  final cents =
      int.parse(units) * 100 + int.parse(decimalsPart.padRight(2, '0'));
  return cents;
}

/// [parseEuroCents] without the throw, for live validation while typing.
///
/// Returns a record because null is a valid parse result ("no cost"), so a
/// bare null could not distinguish it from a malformed amount.
({bool valid, int? cents}) tryParseEuroCents(String raw) {
  try {
    return (valid: true, cents: parseEuroCents(raw));
  } on FormatException {
    return (valid: false, cents: null);
  }
}

/// What to put in the cost field when editing an existing amount.
String euroEditingValue(int? cents) {
  if (cents == null) return '';
  final units = cents ~/ 100;
  final decimals = cents % 100;
  return decimals == 0
      ? '$units'
      : '$units,${decimals.toString().padLeft(2, '0')}';
}
