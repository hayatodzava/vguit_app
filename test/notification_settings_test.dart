import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/schedule_notification_settings.dart';
import 'package:vguit_app/services/notifications/group_snapshot.dart';

/// Книга с двумя группами: у У-261 пара только в числителе/знаменателе,
/// у У-262 — отдельные занятия.
Uint8List workbook({required String mondayLesson}) {
  final excel = Excel.createExcel();
  const sheet = '1 курс';
  final table = excel[sheet];
  excel.setDefaultSheet(sheet);
  excel.delete('Sheet1');

  void row(List<String> values) {
    table.appendRow(values.map<CellValue?>((v) => TextCellValue(v)).toList());
  }

  row(['ДНИ', 'ВРЕМЯ', 'У-261', 'У-262']);
  row(['ПОНЕДЕЛЬНИК', '8.00-9.30', mondayLesson, 'История']);
  row(['', '', 'Физика', 'История']);
  row(['ВТОРНИК', '10.00-11.30', 'Химия', 'Право']);

  return Uint8List.fromList(excel.encode()!);
}

GroupSnapshotResult snapshots(Uint8List bytes, List<String> groups) =>
    buildGroupSnapshots(GroupSnapshotRequest(bytes: bytes, groups: groups));

void main() {
  group('снимок расписания группы', () {
    test('находит группы и их пары', () {
      final result = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
        'У-262',
      ]);

      expect(result.missing, isEmpty);
      expect(result.snapshots.keys, containsAll(['У-261', 'У-262']));
      expect(result.snapshots['У-261']!.course, '1 курс');
      expect(result.snapshots['У-261']!.cells, hasLength(2));
      expect(
        result.snapshots['У-261']!.cells['Понедельник|8.00-9.30'],
        'Математика|Физика',
      );
    });

    test('отмечает группы, которых нет в файле', () {
      final result = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
        'У-999',
      ]);

      expect(result.missing, ['У-999']);
      expect(result.snapshots.keys, ['У-261']);
    });
  });

  group('сравнение снимков', () {
    test('изменение пары видно в diff', () {
      final before = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
      ]).snapshots['У-261']!;
      final after = snapshots(workbook(mondayLesson: 'Информатика'), [
        'У-261',
      ]).snapshots['У-261']!;

      final diff = after.diff(before);
      expect(diff, isNotEmpty);
      expect(diff.first, contains('изменена пара'));
      expect(diff.first, contains('Понедельник'));
    });

    test('без изменений diff пустой', () {
      final before = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
      ]).snapshots['У-261']!;
      final after = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
      ]).snapshots['У-261']!;

      expect(after.diff(before), isEmpty);
    });

    test('снимок переживает JSON', () {
      final original = snapshots(workbook(mondayLesson: 'Математика'), [
        'У-261',
      ]).snapshots['У-261']!;

      final restored = decodeSnapshot(
        '{"course":"${original.course}","cells":'
        '${_jsonCells(original.cells)}}',
      );

      expect(restored, isNotNull);
      expect(restored!.course, original.course);
      expect(restored.cells, original.cells);
    });
  });

  group('расписание проверок', () {
    const daily = ScheduleNotificationSettings(
      enabled: true,
      faculty: 'УИТС',
      groups: <String>['У-261'],
      hour: 8,
      minute: 30,
    );

    test('ежедневно: ближайшее наступление времени', () {
      expect(
        daily.nextRun(DateTime(2026, 11, 8, 7, 0)),
        DateTime(2026, 11, 8, 8, 30),
      );
      expect(
        daily.nextRun(DateTime(2026, 11, 8, 9, 0)),
        DateTime(2026, 11, 9, 8, 30),
      );
    });

    test('раз в неделю: нужный день и время', () {
      const weekly = ScheduleNotificationSettings(
        enabled: true,
        frequency: ScheduleCheckFrequency.weekly,
        weekday: DateTime.wednesday,
        faculty: 'УИТС',
        groups: <String>['У-261'],
        hour: 8,
        minute: 0,
      );

      // 8 ноября 2026 — воскресенье.
      final next = weekly.nextRun(DateTime(2026, 11, 8, 10, 0));
      expect(next, DateTime(2026, 11, 11, 8, 0));
      expect(next.weekday, DateTime.wednesday);

      // В тот же день, но раньше времени — сегодня.
      expect(
        weekly.nextRun(DateTime(2026, 11, 11, 7, 0)),
        DateTime(2026, 11, 11, 8, 0),
      );
      // Время прошло — через неделю.
      expect(
        weekly.nextRun(DateTime(2026, 11, 11, 9, 0)),
        DateTime(2026, 11, 18, 8, 0),
      );
    });

    test('настройки сериализуются и читаются', () {
      final restored = ScheduleNotificationSettings.fromJson(daily.toJson());

      expect(restored.enabled, isTrue);
      expect(restored.faculty, 'УИТС');
      expect(restored.groups, ['У-261']);
      expect(restored.timeLabel, '08:30');
      expect(restored.frequency, ScheduleCheckFrequency.daily);
    });

    test('неполные настройки не запускают проверку', () {
      expect(daily.isComplete, isTrue);
      expect(daily.copyWith(groups: const <String>[]).isComplete, isFalse);
      expect(daily.copyWith(clearFaculty: true).isComplete, isFalse);
      expect(daily.copyWith(enabled: false).isComplete, isFalse);
    });
  });
}

String _jsonCells(Map<String, String> cells) {
  final entries = cells.entries
      .map((entry) => '"${entry.key}":"${entry.value}"')
      .join(',');
  return '{$entries}';
}
