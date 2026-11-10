import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';

import '../../background/schedule_update_task.dart';
import '../../models/schedule_notification_settings.dart';

/// Планирование фоновой проверки расписания будильником Android.
///
/// Используется `AlarmManager` через плагин `android_alarm_manager_plus`:
/// будильник поднимает фоновый изолят Dart, поэтому проверка проходит,
/// когда приложение закрыто.
class ScheduleAlarmScheduler {
  const ScheduleAlarmScheduler();

  /// Идентификатор единственного будильника (повторный вызов заменяет его).
  static const int alarmId = 4201;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  /// Перепланировать будильник под текущие настройки.
  Future<bool> apply(ScheduleNotificationSettings settings) async {
    if (!isSupported) return false;
    try {
      await AndroidAlarmManager.initialize();
      await AndroidAlarmManager.cancel(alarmId);
      if (!settings.isComplete) return true;
      return await scheduleNext(settings);
    } catch (error) {
      debugPrint('[alarm] не удалось перепланировать: $error');
      return false;
    }
  }

  /// Поставить будильник на ближайшее время из настроек.
  Future<bool> scheduleNext(ScheduleNotificationSettings settings) async {
    if (!isSupported || !settings.isComplete) return false;

    final next = settings.nextRun(DateTime.now());
    final params = <String, dynamic>{'at': next.toIso8601String()};

    // Точный будильник требует разрешения SCHEDULE_EXACT_ALARM
    // (Android 14+ выдаёт его только через настройки системы).
    if (await _register(next, params, exact: true)) return true;
    // Без разрешения — неточный, но с пробуждением и в обход Doze.
    return _register(next, params, exact: false);
  }

  Future<bool> _register(
    DateTime time,
    Map<String, dynamic> params, {
    required bool exact,
  }) async {
    try {
      final scheduled = await AndroidAlarmManager.oneShotAt(
        time,
        alarmId,
        scheduleUpdateCallback,
        exact: exact,
        allowWhileIdle: true,
        wakeup: true,
        rescheduleOnReboot: true,
        params: params,
      );
      if (scheduled) {
        debugPrint(
          '[alarm] проверка расписания запланирована на $time '
          '(точный: $exact)',
        );
      }
      return scheduled;
    } catch (error) {
      debugPrint('[alarm] ошибка планирования (точный: $exact): $error');
      return false;
    }
  }

  /// Снимает будильник (например, когда уведомления отключили).
  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await AndroidAlarmManager.cancel(alarmId);
    } catch (error) {
      debugPrint('[alarm] не удалось отменить: $error');
    }
  }
}
