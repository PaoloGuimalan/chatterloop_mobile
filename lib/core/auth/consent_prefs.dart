import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence of the account's pending policy consents captured from
/// the last authoritative (Django login/tp_auth) response, so session
/// RESTORE can gate on them too.
///
/// The Node jwtchecker used on restore only reports profile completeness
/// (transformUser computes isComplete = birthdate && gender) - it never
/// reports consent state, and there's no read-only server endpoint that
/// returns pending consents. So we remember them here: written on
/// login/signup, read on restore (auth_controller), and cleared once the
/// Setup screen records acceptance. Just document_type strings - not
/// sensitive, hence shared_preferences rather than secure storage.
class ConsentPrefs {
  static const _key = 'pending_consents';

  static Future<void> save(List<String> consents) async {
    final prefs = await SharedPreferences.getInstance();
    if (consents.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setStringList(_key, consents);
    }
  }

  static Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
