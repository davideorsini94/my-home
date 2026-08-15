/// FNV-1a hash folded into 31 bits.
///
/// Android notification ids are Java `int`s, and they must stay stable across
/// app releases so that rescheduling replaces an existing pending notification
/// instead of creating a duplicate. `String.hashCode` gives no such guarantee,
/// so the hash is computed explicitly here.
int stableNotificationId(String input) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  const int mask32 = 0xFFFFFFFF;

  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash = (hash ^ unit) & mask32;
    hash = (hash * prime) & mask32;
  }
  // Drop the sign bit: notification ids must be non-negative.
  return hash & 0x7FFFFFFF;
}
