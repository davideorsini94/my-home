import 'package:shared_preferences/shared_preferences.dart';

/// Disk queue for notification confirmations that could not be written when the
/// action was tapped.
///
/// Firestore already persists queued writes across restarts, so this is only
/// the belt-and-braces path for the case where the background isolate fails
/// before it even reaches Firestore — a cold start where initialisation throws,
/// for instance. Replaying is safe because scheduled collections use
/// deterministic document ids, so a duplicate replay simply overwrites.
class PendingActionsStore {
  const PendingActionsStore();

  static const _key = 'pending_notification_actions';

  Future<void> add(String encodedPayload) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    if (current.contains(encodedPayload)) return;
    current.add(encodedPayload);
    await prefs.setStringList(_key, current);
  }

  Future<List<String>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    if (current.isNotEmpty) await prefs.remove(_key);
    return current;
  }
}
