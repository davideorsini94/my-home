import '../core/local_date.dart';
import '../core/waste_catalogue.dart';
import 'entities/collection_event.dart';

/// Rules about collection identity, kept free of Firestore so they can be
/// reasoned about and tested on their own.
///
/// The whole multi-user counting story rests on these: a scheduled pickup maps
/// to one id no matter who records it or from where, while an extra maps to a
/// fresh id every time.
const _extraMarker = '_x_';

/// The document id an event should live under, given its type and date.
String idForEvent({
  required WasteType type,
  required LocalDate date,
  required bool isExtra,
  required String uniqueSuffix,
}) => isExtra
    ? CollectionEvent.extraId(type, date, uniqueSuffix)
    : CollectionEvent.scheduledId(type, date);

/// Recovers the random suffix of an extra's id, so that editing an extra keeps
/// it distinct from any sibling extra on the same day.
String extraSuffixOf(String id) {
  final index = id.lastIndexOf(_extraMarker);
  return index < 0 ? id : id.substring(index + _extraMarker.length);
}

/// Whether moving [original] to ([type], [date]) lands on an id that is already
/// taken, i.e. whether the two records would collapse into one.
///
/// Only scheduled collections can merge: one scheduled pickup of one type on
/// one day is one collection, so merging is the arithmetically correct outcome.
/// Extras never merge, because two extra bags on the same day really are two.
bool wouldMergeOnMove({
  required CollectionEvent original,
  required WasteType type,
  required LocalDate date,
  required Iterable<CollectionEvent> existing,
}) {
  if (original.isExtra) return false;
  final newId = CollectionEvent.scheduledId(type, date);
  if (newId == original.id) return false;
  return existing.any((e) => e.id == newId);
}
