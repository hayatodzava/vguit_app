import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/services/schedule_sources.dart';

/// Книга факультета с двумя листами-курсами.
Uint8List workbook() {
  final excel = Excel.createExcel();

  void fill(String sheetName, List<String> groups) {
    final sheet = excel[sheetName];
    sheet.appendRow(<CellValue?>[
      TextCellValue('ДНИ'),
      TextCellValue('ВРЕМЯ'),
      ...groups.map<CellValue?>((g) => TextCellValue(g)),
    ]);
    sheet.appendRow(<CellValue?>[
      TextCellValue('ПОНЕДЕЛЬНИК'),
      TextCellValue('8.00-9.30'),
      ...groups.map<CellValue?>((_) => TextCellValue('Математика')),
    ]);
  }

  fill('1 курс', <String>['У-261', 'У-262']);
  fill('2 курс', <String>['У-361']);

  excel.delete('Sheet1');
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  group('каталог групп факультета', () {
    test('группы собираются со всех курсов', () {
      final courses = ScheduleSources.groupCourses(workbook());

      expect(courses, hasLength(3));
      expect(courses['У-261'], '1 курс');
      expect(courses['У-262'], '1 курс');
      expect(courses['У-361'], '2 курс');
    });

    test('список групп отсортирован и содержит все курсы', () {
      final names = ScheduleSources.groupNames(workbook());

      expect(names, ['У-261', 'У-262', 'У-361']);
    });

    test('пустая книга даёт пустой каталог', () {
      final excel = Excel.createExcel();
      final bytes = Uint8List.fromList(excel.encode()!);

      expect(ScheduleSources.groupCourses(bytes), isEmpty);
      expect(ScheduleSources.groupNames(bytes), isEmpty);
    });
  });
}
