import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/waste_catalogue.dart';
import '../domain/entities/waste_config.dart';
import 'firestore_refs.dart';

class WasteConfigRepository {
  const WasteConfigRepository(this._refs);

  final FirestoreRefs _refs;

  Stream<List<WasteConfig>> watchConfigs(String houseId) =>
      _refs.wasteConfigs(houseId).snapshots().map(_toConfigs);

  Future<List<WasteConfig>> getConfigs(String houseId) async =>
      _toConfigs(await _refs.wasteConfigs(houseId).get());

  List<WasteConfig> _toConfigs(QuerySnapshot<Map<String, dynamic>> snap) {
    final configs = <WasteConfig>[];
    for (final doc in snap.docs) {
      final type = WasteType.fromId(doc.id);
      // A document whose id is not in the catalogue can only come from a newer
      // app version; skipping it is better than crashing an older client.
      if (type == null) continue;
      configs.add(WasteConfig.fromMap(type, doc.data()));
    }
    // Catalogue order, so the UI listing is stable regardless of write order.
    configs.sort((a, b) => a.type.index.compareTo(b.type.index));
    return configs;
  }

  /// The document id is the waste type id, which keeps one configuration per
  /// type per house by construction.
  Future<void> saveConfig(String houseId, WasteConfig config) => _refs
      .wasteConfigs(houseId)
      .doc(config.type.id)
      .set({...config.toMap(), 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> setEnabled(String houseId, WasteType type, bool enabled) =>
      _refs.wasteConfigs(houseId).doc(type.id).set({
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
