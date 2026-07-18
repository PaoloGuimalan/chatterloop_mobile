import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for the Map Feed Access toggles (enable/share location).
/// The webapp stores these client-side only (persistSettings -> localforage,
/// keyed by entity id) - there's no server endpoint - so mobile does the
/// same via shared_preferences, keyed by the account's entity id.
class MapFeedPrefs {
  static String _enableKey(String entityId) => 'map_feed_enable_$entityId';
  static String _shareKey(String entityId) => 'map_feed_share_$entityId';

  /// (enableLocation, shareLocation) - both default to false.
  static Future<(bool, bool)> read(String entityId) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getBool(_enableKey(entityId)) ?? false,
      prefs.getBool(_shareKey(entityId)) ?? false,
    );
  }

  static Future<void> setEnable(String entityId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableKey(entityId), value);
  }

  static Future<void> setShare(String entityId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareKey(entityId), value);
  }
}
