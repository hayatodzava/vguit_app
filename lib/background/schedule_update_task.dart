import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/schedule_notification_settings.dart';
import '../services/net.dart';
import '../services/notifications/notification_store.dart';
import '../services/notifications/schedule_alarm_scheduler.dart';
import '../services/notifications/schedule_notifier.dart';
import '../services/notifications/schedule_watcher.dart';

/// Точка входа фонового изолята: сюда приходит будильник Android.
///
/// Функция должна быть верхнего уровня и помечена `vm:entry-point`,
/// иначе её удалит компилятор в release-сборке.
@pragma('vm:entry-point')
void scheduleUpdateCallback(int id, Map<String, dynamic> params) {
  unawaited(runScheduleCheck());
}

/// Проверка расписания по настройкам: скачать → сравнить → уведомить →
/// запланировать следующую проверку.
///
/// Вызывается и из фона, и кнопкой «Проверить сейчас» в настройках.
Future<ScheduleCheckResult?> runScheduleCheck() async {
  // В фоновом изоляте биндинг нужен для плагинов (SharedPreferences и т.п.).
  WidgetsFlutterBinding.ensureInitialized();

  const store = NotificationStore();
  const watcher = ScheduleWatcher();
  const scheduler = ScheduleAlarmScheduler();

  ScheduleNotificationSettings settings;
  try {
    settings = await store.loadSettings();
  } catch (error) {
    debugPrint('[background] настройки недоступны: $error');
    return null;
  }

  if (!settings.isComplete) {
    await scheduler.cancel();
    return null;
  }

  ScheduleCheckResult? result;
  try {
    result = await watcher.run(settings, useIsolate: false);
  } catch (error) {
    debugPrint(
      '[background] проверка не удалась: '
      '${AppException.from(error).message}',
    );
  }

  if (result != null && result.hasChanges) {
    try {
      await ScheduleNotifier.instance.showScheduleChanged(
        faculty: settings.faculty!,
        groups: result.changedGroups,
        changes: result.changes,
      );
    } catch (error) {
      debugPrint('[background] уведомление не отправлено: $error');
    }
  }

  // Следующая проверка — даже если текущая не удалась,
  // иначе цепочка будильников оборвётся.
  try {
    await scheduler.scheduleNext(settings);
  } catch (error) {
    debugPrint(
      '[background] не удалось запланировать следующую проверку: '
      '$error',
    );
  }

  return result;
}
