import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/schedule.dart';
import 'package:vguit_app/services/schedule_parser.dart';

/// Собирает книгу в том же виде, что отдаёт сайт вуза:
/// шапка «ДНИ | ВРЕМЯ | группы», пары строк числитель/знаменатель.
Uint8List buildSampleWorkbook() {
  final excel = Excel.createExcel();
  const sheetName = '1 курс';
  final sheet = excel[sheetName];
  excel.setDefaultSheet(sheetName);
  excel.delete('Sheet1');

  void row(List<String> values) {
    sheet.appendRow(values.map<CellValue?>((v) => TextCellValue(v)).toList());
  }

  // У-262 занимает две колонки — значит, у группы две подгруппы.
  row(['ДНИ', 'ВРЕМЯ', 'У-261', 'У-262', '']);
  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
    CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0),
  );

  // Числитель и знаменатель отдельными строками.
  row(['ПОНЕДЕЛЬНИК', '8.00-9.30', 'Математика', 'Ин.яз', 'Ин.яз2']);
  row(['', '', 'Физика', 'Ин.яз', 'Физ-ра']);

  // Занятие только по чётной неделе: числитель пустой.
  row(['ВТОРНИК', '8.00-9.30', '', '', '']);
  row(['', '', 'Химия', 'История', 'История']);

  // Слот без знаменателя.
  row(['СРЕДА', '10.00-11.30', 'Философия', 'Право', 'Право']);

  return Uint8List.fromList(excel.encode()!);
}

void main() {
  late ScheduleData data;

  setUpAll(() {
    data = ScheduleParser.parse(
      excel: Excel.decodeBytes(buildSampleWorkbook()),
      sheetName: '1 курс',
      faculty: 'УИТС',
    );
  });

  LessonCell? cell(String day, String time, String group) =>
      data.lessons[day]?[time]?[group];

  test('группы и подгруппы определяются по шапке', () {
    expect(data.groupCols.map((g) => g.name), ['У-261', 'У-262']);
    expect(data.groupCols.first.hasSubgroups, isFalse);
    expect(data.groupCols.last.hasSubgroups, isTrue);
  });

  test('слоты собираются и сортируются по времени', () {
    expect(data.timeSlots, ['8.00-9.30', '10.00-11.30']);
    expect(data.lessons.keys, containsAll(['Понедельник', 'Вторник', 'Среда']));
  });

  test('числитель и знаменатель читаются из соседних строк', () {
    final lesson = cell('Понедельник', '8.00-9.30', 'У-261');
    expect(lesson, isNotNull);
    expect(lesson!.numerator, 'Математика');
    expect(lesson.denominator, 'Физика');
    expect(lesson.hasTwoWeeks, isTrue);
  });

  test('занятие только по чётной неделе не попадает в числитель', () {
    final lesson = cell('Вторник', '8.00-9.30', 'У-261');
    expect(lesson, isNotNull);
    expect(lesson!.numerator, isEmpty);
    expect(lesson.denominator, 'Химия');
  });

  test('подгруппы читаются по своим колонкам', () {
    final lesson = cell('Понедельник', '8.00-9.30', 'У-262')!;
    expect(lesson.hasSubgroups, isTrue);
    expect(lesson.sub1Num, 'Ин.яз');
    expect(lesson.sub2Num, 'Ин.яз2');
    expect(lesson.sub1Den, 'Ин.яз');
    expect(lesson.sub2Den, 'Физ-ра');
  });

  test('слот без знаменателя остаётся однострочным', () {
    final lesson = cell('Среда', '10.00-11.30', 'У-261')!;
    expect(lesson.numerator, 'Философия');
    expect(lesson.denominator, isEmpty);
    expect(lesson.hasTwoWeeks, isFalse);
  });

  test('неизвестный лист даёт понятную ошибку', () {
    expect(
      () => ScheduleParser.parse(
        excel: Excel.decodeBytes(buildSampleWorkbook()),
        sheetName: '9 курс',
        faculty: 'УИТС',
      ),
      throwsA(predicate((error) => '$error'.contains('нет листа'))),
    );
  });

  test('обёртка для изолята разбирает ту же книгу', () {
    final parsed = parseScheduleInBackground(
      ScheduleParseRequest(
        bytes: buildSampleWorkbook(),
        sheetName: '1 курс',
        faculty: 'УИТС',
      ),
    );
    expect(parsed.groupCols, hasLength(2));
    expect(parsed.timeSlots, isNotEmpty);
  });
}
