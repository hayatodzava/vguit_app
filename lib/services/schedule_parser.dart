import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;

import '../models/schedule.dart';
import 'net.dart';

/// Запрос на разбор книги расписания в отдельном изоляте.
///
/// В изолят уходят только байты и строки — сам файл там же и разбирается,
/// поэтому интерфейс не подвисает на больших xlsx.
class ScheduleParseRequest {
  const ScheduleParseRequest({
    required this.bytes,
    required this.sheetName,
    required this.faculty,
  });

  final Uint8List bytes;
  final String sheetName;
  final String faculty;
}

/// Точка входа для `compute()`.
ScheduleData parseScheduleInBackground(ScheduleParseRequest request) {
  final excel = Excel.decodeBytes(request.bytes);
  return ScheduleParser.parse(
    excel: excel,
    sheetName: request.sheetName,
    faculty: request.faculty,
  );
}

class ScheduleParser {
  static const _days = [
    'ПОНЕДЕЛЬНИК',
    'ВТОРНИК',
    'СРЕДА',
    'ЧЕТВЕРГ',
    'ПЯТНИЦА',
    'СУББОТА',
    'ВОСКРЕСЕНЬЕ',
  ];

  static ScheduleData parse({
    required Excel excel,
    required String sheetName,
    required String faculty,
  }) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) {
      final available = excel.tables.keys.join(', ');
      throw AppException.parse(
        'В файле расписания нет листа «$sheetName». '
        'Доступные листы: $available.',
      );
    }

    final rows = sheet.rows;

    // 1. Собираем объединённые ячейки.
    //    getMergedCells возвращает список строк вида "A1:B2" или "C5".
    //    Нам нужна карта: для каждой "ведомой" ячейки — ссылка на "главную".
    //    Главная ячейка — та, что в левом верхнем углу объединения.
    final mergedMap = <String, String>{}; // "B2" -> "A2"
    try {
      final merged = excel.getMergedCells(sheetName);
      for (final range in merged) {
        final cells = _expandMergedRange(range);
        if (cells.isEmpty) continue;
        final master = cells.first;
        for (final cell in cells) {
          mergedMap[cell] = master;
        }
      }
    } catch (_) {
      // Если API недоступен — работаем без объединённых ячеек.
    }

    // 2. Заголовок групп
    int headerRowIndex = -1;
    for (int i = 0; i < rows.length; i++) {
      final firstCell = _cellText(rows[i], 0).trim().toUpperCase();
      if (firstCell == 'ДНИ') {
        headerRowIndex = i;
        break;
      }
    }
    if (headerRowIndex == -1) {
      throw AppException.parse(
        'Не найдена строка заголовков «ДНИ» — файл расписания другого формата.',
      );
    }

    // 3. Читаем группы и подгруппы.
    //    Используем mergedMap для определения, объединена ли ячейка шапки
    //    с соседней. Если да — у группы две подгруппы.
    final groups = <_GroupCol>[];
    final headerRow = rows[headerRowIndex];

    int c = 2;
    while (c < headerRow.length) {
      final name = _cellText(headerRow, c).trim();
      if (name.isEmpty) {
        c++;
        continue;
      }

      // Проверяем, объединена ли ячейка (c, headerRowIndex) с (c+1, headerRowIndex).
      // Если да — значит группа занимает два столбца => две подгруппы.
      bool hasSubgroup = false;
      if (c + 1 < headerRow.length) {
        final cellId = _colIndexToLetter(c) + (headerRowIndex + 1).toString();
        final nextCellId =
            _colIndexToLetter(c + 1) + (headerRowIndex + 1).toString();
        // Ячейка (c+1) — ведомая для (c)? Значит, они объединены.
        if (mergedMap[nextCellId] == cellId) {
          hasSubgroup = true;
        }
      }

      groups.add(
        _GroupCol(name: name, mainCol: c, subCol: hasSubgroup ? c + 1 : -1),
      );

      c += hasSubgroup ? 2 : 1;
    }

    // 4. Читаем данные.
    //
    //    Структура листа: строка дня, затем пары строк «время + пары».
    //    Внутри пары первая строка — числитель, вторая (без дня и времени)
    //    — знаменатель. Раньше знаменатель определялся по содержимому
    //    («числитель уже заполнен»), из-за чего занятие только по чётной
    //    неделе попадало в числитель. Теперь позиция строки однозначна.
    final lessons = <String, Map<String, Map<String, _LessonCell>>>{};
    final timeSlots = <String>[];
    var currentDay = '';

    for (var r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      final colA = _cellText(row, 0).trim();
      final colB = _cellText(row, 1).trim();

      if (_isDayHeader(colA)) {
        currentDay = _normalizeDay(colA);
        lessons.putIfAbsent(currentDay, () => {});
        // Не выходим: в этой же строке обычно стоит и первая пара дня.
      }

      if (currentDay.isEmpty || !_looksLikeTime(colB)) continue;

      final time = colB;
      if (!timeSlots.contains(time)) timeSlots.add(time);
      final slot = lessons
          .putIfAbsent(currentDay, () => {})
          .putIfAbsent(time, () => {});

      final numeratorRow = r;
      var denominatorRow = -1;
      if (r + 1 < rows.length) {
        final nextRow = rows[r + 1];
        final nextA = _cellText(nextRow, 0).trim();
        final nextB = _cellText(nextRow, 1).trim();
        final nextIsTime = _looksLikeTime(nextB);
        // Знаменатель — следующая строка без дня. Время в ней либо пустое
        // (объединённая ячейка), либо повторяет текущее.
        final nextRepeatsTime = nextB.isNotEmpty && nextB == time;
        if (!_isDayHeader(nextA) && (!nextIsTime || nextRepeatsTime)) {
          denominatorRow = r + 1;
        }
      }

      for (final group in groups) {
        final numMain = _cellValue(
          rows,
          mergedMap,
          numeratorRow,
          group.mainCol,
        );
        final denMain = denominatorRow < 0
            ? ''
            : _cellValue(rows, mergedMap, denominatorRow, group.mainCol);
        final numSub = group.subCol < 0
            ? ''
            : _cellValue(rows, mergedMap, numeratorRow, group.subCol);
        final denSub = (group.subCol < 0 || denominatorRow < 0)
            ? ''
            : _cellValue(rows, mergedMap, denominatorRow, group.subCol);

        if (numMain.isEmpty &&
            denMain.isEmpty &&
            numSub.isEmpty &&
            denSub.isEmpty) {
          continue;
        }

        if (group.subCol >= 0) {
          slot[group.name] = _LessonCell(
            sub1Num: numMain,
            sub2Num: numSub,
            sub1Den: denMain,
            sub2Den: denSub,
            hasSubgroups: true,
          );
        } else {
          slot[group.name] = _LessonCell(
            numerator: numMain,
            denominator: denMain,
          );
        }
      }

      // Строка знаменателя уже прочитана — перешагиваем её.
      if (denominatorRow >= 0) r = denominatorRow;
    }

    timeSlots.sort((a, b) => _timeToMinutes(a).compareTo(_timeToMinutes(b)));

    return ScheduleData(
      faculty: faculty,
      course: sheetName,
      groups: groups.map((g) => g.name).toList(),
      groupCols: groups
          .map((g) => GroupInfo(name: g.name, hasSubgroups: g.subCol >= 0))
          .toList(),
      timeSlots: timeSlots,
      lessons: _convertLessons(lessons),
    );
  }

  // ── Вспомогательные методы для работы с объединёнными ячейками ──

  /// Значение ячейки с учётом объединения: у «ведомой» ячейки берётся
  /// значение главной.
  static String _cellValue(
    List<List<Data?>> rows,
    Map<String, String> mergedMap,
    int rowIndex,
    int colIndex,
  ) {
    if (rowIndex < 0 || rowIndex >= rows.length) return '';
    final row = rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.length) return '';

    final cellId = _colIndexToLetter(colIndex) + (rowIndex + 1).toString();
    final masterId = mergedMap[cellId];
    if (masterId != null && masterId != cellId) {
      final masterCol = _letterToColIndex(
        masterId.replaceAll(RegExp(r'\d'), ''),
      );
      final masterRow = int.tryParse(masterId.replaceAll(RegExp(r'[A-Z]'), ''));
      if (masterRow != null) {
        final rowIndex2 = masterRow - 1;
        if (rowIndex2 >= 0 &&
            rowIndex2 < rows.length &&
            masterCol >= 0 &&
            masterCol < rows[rowIndex2].length) {
          return _cellText(rows[rowIndex2], masterCol).trim();
        }
      }
      return '';
    }
    return _cellText(row, colIndex).trim();
  }

  /// Разворачивает диапазон "A1:B2" в список ID ячеек: ["A1","B1","A2","B2"].
  static List<String> _expandMergedRange(String range) {
    final parts = range.split(':');
    if (parts.length == 1) return [parts[0]];
    if (parts.length != 2) return [];

    final start = parts[0];
    final end = parts[1];

    final startCol = _letterToColIndex(start.replaceAll(RegExp(r'\d'), ''));
    final startRow = int.tryParse(start.replaceAll(RegExp(r'[A-Z]'), '')) ?? 0;
    final endCol = _letterToColIndex(end.replaceAll(RegExp(r'\d'), ''));
    final endRow = int.tryParse(end.replaceAll(RegExp(r'[A-Z]'), '')) ?? 0;

    final cells = <String>[];
    for (int r = startRow; r <= endRow; r++) {
      for (int c = startCol; c <= endCol; c++) {
        cells.add(_colIndexToLetter(c) + r.toString());
      }
    }
    return cells;
  }

  static int _letterToColIndex(String letters) {
    int result = 0;
    for (int i = 0; i < letters.length; i++) {
      result = result * 26 + (letters.codeUnitAt(i) - 64);
    }
    return result - 1;
  }

  static String _colIndexToLetter(int index) {
    String result = '';
    int n = index + 1;
    while (n > 0) {
      int rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  static Map<String, Map<String, Map<String, LessonCell>>> _convertLessons(
    Map<String, Map<String, Map<String, _LessonCell>>> raw,
  ) {
    final result = <String, Map<String, Map<String, LessonCell>>>{};
    raw.forEach((day, times) {
      result[day] = {};
      times.forEach((time, groups) {
        result[day]![time] = {};
        groups.forEach((group, cell) {
          result[day]![time]![group] = LessonCell(
            numerator: cell.numerator,
            denominator: cell.denominator,
            sub1Num: cell.sub1Num,
            sub1Den: cell.sub1Den,
            sub2Num: cell.sub2Num,
            sub2Den: cell.sub2Den,
            hasSubgroups: cell.hasSubgroups,
          );
        });
      });
    });
    return result;
  }

  static String _cellText(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final cell = row[index];
    if (cell == null) return '';
    final v = cell.value;
    if (v == null) return '';
    return v.toString();
  }

  static bool _isDayHeader(String text) {
    if (text.isEmpty) return false;
    final upper = text.toUpperCase();
    return _days.any(upper.contains);
  }

  static bool _looksLikeTime(String s) {
    final re = RegExp(r'\d{1,2}[.:]\d{2}\s*[-–—]\s*\d{1,2}[.:]\d{2}');
    return re.hasMatch(s);
  }

  static int _timeToMinutes(String s) {
    final re = RegExp(r'(\d{1,2})[.:](\d{2})');
    final m = re.firstMatch(s);
    if (m == null) return 0;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static String _normalizeDay(String raw) {
    final upper = raw.toUpperCase().trim();
    for (final d in _days) {
      if (upper.contains(d)) {
        return d[0] + d.substring(1).toLowerCase();
      }
    }
    return raw;
  }
}

class _GroupCol {
  final String name;
  final int mainCol;
  final int subCol;
  _GroupCol({required this.name, required this.mainCol, required this.subCol});
}

class _LessonCell {
  final String numerator;
  final String denominator;
  final String sub1Num;
  final String sub1Den;
  final String sub2Num;
  final String sub2Den;
  final bool hasSubgroups;
  _LessonCell({
    this.numerator = '',
    this.denominator = '',
    this.sub1Num = '',
    this.sub1Den = '',
    this.sub2Num = '',
    this.sub2Den = '',
    this.hasSubgroups = false,
  });
}
