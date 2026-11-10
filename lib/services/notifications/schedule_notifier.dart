import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Показ уведомлений о расписании.
class ScheduleNotifier {
  ScheduleNotifier._();

  static final ScheduleNotifier instance = ScheduleNotifier._();

  static const String _channelId = 'schedule_changes';
  static const String _channelName = 'Изменения расписания';
  static const String _channelDescription =
      'Уведомления об изменениях расписания студентов';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Инициализация. Безопасно вызывать повторно и из фонового изолята.
  Future<void> initialize() async {
    if (_initialized) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      _initialized = true;
      return;
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialized = true;
    } catch (error) {
      // Уведомления — вспомогательная функция: не роняем приложение,
      // если плагин недоступен (например, в тестах).
      debugPrint('[notify] инициализация недоступна: $error');
    }
  }

  /// Запрашивает разрешение на уведомления (Android 13+ и iOS).
  Future<bool> requestPermission() async {
    await initialize();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      }
    } catch (error) {
      debugPrint('[notify] запрос разрешения не удался: $error');
    }
    return false;
  }

  /// Можно ли ставить точные будильники (Android 12+).
  Future<bool> canScheduleExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    await initialize();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (error) {
      debugPrint('[notify] проверка точных будильников не удалась: $error');
      return false;
    }
  }

  /// Открывает системный экран «Будильники и напоминания».
  Future<bool> requestExactAlarmPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    await initialize();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestExactAlarmsPermission() ?? false;
    } catch (error) {
      debugPrint('[notify] запрос точных будильников не удался: $error');
      return false;
    }
  }

  /// Уведомление «расписание изменилось».
  Future<void> showScheduleChanged({
    required String faculty,
    required List<String> groups,
    Map<String, List<String>> changes = const <String, List<String>>{},
  }) async {
    await initialize();

    final groupList = groups.join(', ');
    final details = groups.length == 1
        ? (changes[groups.first]?.take(2).join('; ') ?? '')
        : '';
    final body = details.isEmpty
        ? 'Факультет $faculty, группы: $groupList. '
              'Откройте приложение, чтобы посмотреть.'
        : 'Группа $groupList: $details.';

    try {
      await _plugin.show(
        id: 1001,
        title: 'Расписание изменилось',
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'schedule',
      );
    } catch (error) {
      debugPrint('[notify] не удалось показать уведомление: $error');
    }
  }
}
