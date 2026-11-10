import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;

import '../../models/schedule.dart';
import '../schedule_parser.dart';

/// Запрос на снимок расписания выбранных групп.
class GroupSnapshotRequest {
  const GroupSnapshotRequest({required this.bytes, required this.groups});

  final Uint8List bytes;
  final List<String> groups;
}

/// Снимок расписания одной группы: строки «день|время» → содержимое ячейки.
class GroupScheduleSnapshot {
  const GroupScheduleSnapshot({required this.course, required this.cells});

  final String course;
  final Map<String, String> cells;

  Map<String, Object?> toJson() => <String, Object?>{
    'course': course,
    'cells': cells,
  };

  static GroupScheduleSnapshot? fromJson(Map<String, Object?> json) {
    final course = json['course'];
    final cells = json['cells'];
    if (course is! String || cells is! Map) return null;
    return GroupScheduleSnapshot(
      course: course,
      cells: cells.map((key, value) => MapEntry(key.toString(), '$value')),
    );
  }

  /// Чем именно отличаются снимки — для текста уведомления.
  List<String> diff(GroupScheduleSnapshot previous) {
    final changes = <String>[];

    for (final entry in cells.entries) {
      final before = previous.cells[entry.key];
      if (before == null) {
        changes.add('добавлена пара ${_slot(entry.key)}');
      } else if (before != entry.value) {
        changes.add('изменена пара ${_slot(entry.key)}');
      }
    }
    for (final key in previous.cells.keys) {
      if (!cells.containsKey(key)) {
        changes.add('снята пара ${_slot(key)}');
      }
    }
    return changes;
  }

  static String _slot(String key) {
    final parts = key.split('|');
    if (parts.length != 2) return key;
    return '${parts[0]}, ${parts[1]}';
  }
}

/// Результат построения снимков.
class GroupSnapshotResult {
  const GroupSnapshotResult({required this.snapshots, required this.missing});

  /// Только найденные группы.
  final Map<String, GroupScheduleSnapshot> snapshots;

  /// Группы, которых нет ни на одном листе.
  final List<String> missing;
}

/// Строит снимки расписания для перечисленных групп по файлу факультета.
///
/// Функция чистая и подходит для `compute()`: принимает только байты и имена
/// групп, возвращает простые данные.
GroupSnapshotResult buildGroupSnapshots(GroupSnapshotRequest request) {
  final excel = Excel.decodeBytes(request.bytes);
  final remaining = <String>{...request.groups};
  final snapshots = <String, GroupScheduleSnapshot>{};

  for (final sheetName in excel.tables.keys) {
    if (remaining.isEmpty) break;

    late final ScheduleData data;
    try {
      data = ScheduleParser.parse(
        excel: excel,
        sheetName: sheetName,
        faculty: '',
      );
    } catch (_) {
      // Лист другого формата (например, титульный) — пропускаем.
      continue;
    }

    for (final group in remaining.toList()) {
      final cells = <String, String>{};
      data.lessons.forEach((day, times) {
        times.forEach((time, byGroup) {
          final cell = byGroup[group];
          if (cell == null || cell.isEmpty) return;
          cells['$day|$time'] = _cellText(cell);
        });
      });
      if (cells.isEmpty) continue;

      snapshots[group] = GroupScheduleSnapshot(course: sheetName, cells: cells);
      remaining.remove(group);
    }
  }

  return GroupSnapshotResult(
    snapshots: snapshots,
    missing: remaining.toList(growable: false),
  );
}

/// Текст ячейки без форматирования — по нему и сравниваем.
String _cellText(LessonCell cell) {
  if (cell.hasSubgroups) {
    return [
      cell.sub1Num,
      cell.sub1Den,
      cell.sub2Num,
      cell.sub2Den,
    ].map((part) => _normalize(part)).join('|');
  }
  return '${_normalize(cell.numerator)}|${_normalize(cell.denominator)}';
}

String _normalize(String text) => text
    .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Читает сохранённый снимок из JSON-строки.
GroupScheduleSnapshot? decodeSnapshot(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return GroupScheduleSnapshot.fromJson(decoded.cast<String, Object?>());
  } catch (_) {
    return null;
  }
}
