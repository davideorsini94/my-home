/// Phone-number handling for the maintenance contact.
///
/// Deliberately permissive: the number is only ever handed to the system
/// dialer, never validated against a carrier or dialled automatically, so
/// rejecting an unusual but real format would help nobody. Italian landlines,
/// mobiles, international prefixes and internal extensions all pass.
library;

/// Strips what a contact picker and human typing leave behind — spaces,
/// hyphens, dots, brackets and non-breaking spaces — keeping digits, a leading
/// `+`, and the `*`/`#` an extension may need.
String normalizePhone(String raw) {
  final trimmed = raw.trim();
  final buffer = StringBuffer();
  for (var i = 0; i < trimmed.length; i++) {
    final char = trimmed[i];
    final isDigit = char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
    if (isDigit || char == '*' || char == '#') {
      buffer.write(char);
    } else if (char == '+' && buffer.isEmpty) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// Whether [raw] could plausibly be dialled.
///
/// Requires at least three digits, which rejects an empty or junk field while
/// still allowing a short internal extension.
bool isDialablePhone(String raw) {
  final normalized = normalizePhone(raw);
  final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 3;
}

/// The `tel:` URI handed to the dialer.
///
/// Uses the normalised form because a literal space or bracket in a `tel:` URI
/// is not valid percent-encoded syntax and some dialers silently drop it.
Uri telUri(String raw) => Uri(scheme: 'tel', path: normalizePhone(raw));

/// A readable rendering for the confirmation dialog, so the user sees the
/// number the way they wrote it rather than a stripped string.
String formatPhoneForDisplay(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? normalizePhone(raw) : trimmed;
}
