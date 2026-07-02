import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  static const _key = 'unlocked_level';

  static Future<int> getUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  static Future<void> setUnlocked(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key) ?? 0;
    if (index > current) {
      await prefs.setInt(_key, index);
    }
  }
}
