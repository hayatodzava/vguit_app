import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/schedule_notification_settings.dart';
import '../net.dart';

/// Хранилище настроек уведомлений и снимков расписания.
///
/// Ключи живут в своём пространстве имён (`notify_`), поэтому очистка кэша
/// расписания не сбрасывает настройки и не ломает сравнение «было/стало».
class NotificationStore {
  const NotificationStore();

  static const String _settingsKey = 'notify_students_settings';
  static const String _snapshotPrefix = 'notify_snapshot_';
  static const String _lastRunKey = 'notify_last_run';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ─── Настройки ───

  Future<ScheduleNotificationSettings> loadSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const ScheduleNotificationSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ScheduleNotificationSettings();
      return ScheduleNotificationSettings.fromJson(
        decoded.cast<String, Object?>(),
      );
    } catch (error) {
      throw AppException.cache(
        'Настройки уведомлений повреждены. Включите их заново.',
        cause: error,
      );
    }
  }

  Future<void> saveSettings(ScheduleNotificationSettings settings) async {
    final prefs = await _prefs;
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  // ─── Снимки расписания групп ───

  static String _snapshotKey(String faculty, String group) =>
      '$_snapshotPrefix${faculty}_$group';

  Future<String?> readSnapshot(String faculty, String group) async {
    final prefs = await _prefs;
    return prefs.getString(_snapshotKey(faculty, group));
  }

  Future<void> writeSnapshot(String faculty, String group, String json) async {
    final prefs = await _prefs;
    await prefs.setString(_snapshotKey(faculty, group), json);
  }

  Future<void> removeSnapshot(String faculty, String group) async {
    final prefs = await _prefs;
    await prefs.remove(_snapshotKey(faculty, group));
  }

  // ─── Служебное ───

  Future<DateTime?> lastRun() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_lastRunKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markRun(DateTime at) async {
    final prefs = await _prefs;
    await prefs.setString(_lastRunKey, at.toIso8601String());
  }
}
