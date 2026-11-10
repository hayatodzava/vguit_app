import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/schedule_notification_settings.dart';
import '../net.dart';
import '../schedule_cache.dart';
import '../schedule_sources.dart';
import 'group_snapshot.dart';
import 'notification_store.dart';

/// Итог одной проверки расписания.
class ScheduleCheckResult {
  const ScheduleCheckResult({
    required this.checkedAt,
    required this.changedGroups,
    required this.missingGroups,
    this.changes = const <String, List<String>>{},
  });

  final DateTime checkedAt;

  /// Группы, у которых расписание отличается от сохранённого.
  final List<String> changedGroups;

  /// Группы, которых не нашлось в файле (переименованы/расформированы).
  final List<String> missingGroups;

  /// Подробности по каждой изменённой группе.
  final Map<String, List<String>> changes;

  bool get hasChanges => changedGroups.isNotEmpty;

  bool get hasProblem => missingGroups.isNotEmpty;
}

/// Проверка расписания выбранных групп и обновление кэша.
///
/// Порядок: скачать файл → разобрать → сравнить снимки групп с прошлыми →
/// сохранить файл в кэш и новые снимки. Уведомление отправляет вызывающий.
class ScheduleWatcher {
  const ScheduleWatcher();

  static const NotificationStore _store = NotificationStore();
  static const ScheduleCache _cache = ScheduleCache();

  Future<ScheduleCheckResult> run(
    ScheduleNotificationSettings settings, {
    bool useIsolate = true,
  }) async {
    final faculty = settings.faculty;
    final groups = settings.groups;
    if (faculty == null || faculty.isEmpty) {
      throw AppException('Не выбран факультет для отслеживания расписания.');
    }
    if (groups.isEmpty) {
      throw AppException('Не выбрана ни одна группа для отслеживания.');
    }

    final bytes = await ScheduleSources.download(
      faculty,
      action: 'Проверка расписания',
    );

    final request = GroupSnapshotRequest(bytes: bytes, groups: groups);
    final snapshotResult = useIsolate
        ? await compute(buildGroupSnapshots, request)
        : buildGroupSnapshots(request);

    final checkedAt = DateTime.now();
    final changed = <String>[];
    final changes = <String, List<String>>{};

    for (final entry in snapshotResult.snapshots.entries) {
      final group = entry.key;
      final current = entry.value;

      final raw = await _store.readSnapshot(faculty, group);
      final previous = raw == null ? null : decodeSnapshot(raw);

      if (previous == null) {
        // Первый запуск: запоминаем как есть, уведомлять не о чем.
        await _store.writeSnapshot(
          faculty,
          group,
          jsonEncode(current.toJson()),
        );
        continue;
      }

      final diff = current.diff(previous);
      if (diff.isNotEmpty) {
        changed.add(group);
        changes[group] = diff;
      }
      await _store.writeSnapshot(faculty, group, jsonEncode(current.toJson()));
    }

    // Кэш обновляем всегда, как и дату обновления.
    await _cache.saveBytes(faculty, bytes);
    await _store.markRun(checkedAt);

    return ScheduleCheckResult(
      checkedAt: checkedAt,
      changedGroups: List<String>.unmodifiable(changed),
      missingGroups: snapshotResult.missing,
      changes: changes,
    );
  }

  /// Сбрасывает снимки выбранного факультета (после смены групп).
  Future<void> resetSnapshots(String faculty, Iterable<String> groups) async {
    for (final group in groups) {
      await _store.removeSnapshot(faculty, group);
    }
  }
}
