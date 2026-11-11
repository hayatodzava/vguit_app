import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import '../models/rating.dart';

class RatingParser {
  /// Парсит <select id="...cmbFacultets"> — факультеты.
  static List<Faculty> parseFaculties(String html) {
    final doc = html_parser.parse(html);
    final select = doc.querySelector('select[id\$="cmbFacultets"]');
    if (select == null) return [];
    return select.querySelectorAll('option').map((o) {
      return Faculty(id: o.attributes['value'] ?? '', name: o.text.trim());
    }).toList();
  }

  /// Парсит <select id="...cmbGroups"> — группы.
  static List<Group> parseGroups(String html) {
    final doc = html_parser.parse(html);
    final select = doc.querySelector('select[id\$="cmbGroups"]');
    if (select == null) return [];
    return select.querySelectorAll('option').map((o) {
      return Group(id: o.attributes['value'] ?? '', name: o.text.trim());
    }).toList();
  }

  /// Парсит таблицу ucListVedBox_Grid — предметы.
  static List<Subject> parseSubjects(String html) {
    final doc = html_parser.parse(html);
    final table = doc.querySelector('table[id\$="ucListVedBox_Grid"]');
    if (table == null) return [];
    final result = <Subject>[];
    for (final tr in table.querySelectorAll('tr')) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 3) continue;
      final a = tds[0].querySelector('a');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
      if (idMatch == null) continue;
      result.add(
        Subject(
          id: idMatch.group(1)!,
          name: a.text.trim(),
          type: tds[1].text.trim(),
          closed: tds[2].text.trim().toLowerCase() != 'нет',
        ),
      );
    }
    return result;
  }

  /// Парсит страницу ведомости: шапку + таблицу оценок.
  ///
  /// На сайте встречаются две разные таблицы:
  /// - рейтинговая, с контрольными точками («Точка 1», «Вес Точки,%», Лек/Пр/Лаб/Др);
  /// - простая, для экзаменов и пересдач (ФИО, дата сдачи, оценка, подпись).
  static Vedomost parseVedomost(String html, String subjectId) {
    final doc = html_parser.parse(html);

    // ── Шапка
    final groupName = _textById(doc, 'ucVedBox_lblGroup');
    final teacher = _textById(doc, 'ucVedBox_lblPrep');
    final semester = _textById(doc, 'ucVedBox_lblSem');
    final type = _textById(doc, 'ucVedBox_lblTypeVed');
    final year = _textById(doc, 'ucVedBox_lblYear');
    final subjectName = _textById(doc, 'ucVedBox_lblDis');

    final table = doc.querySelector('table[id\$="ucVedBox_tblVed"]');
    final sheet = table == null ? null : _TableGrid.fromTable(table);

    final controlPoints = sheet == null
        ? const <ControlPoint>[]
        : _parseControlPoints(sheet);
    final students = sheet == null
        ? const <StudentRow>[]
        : _parseStudents(sheet, controlPoints);

    return Vedomost(
      subjectId: subjectId,
      subjectName: subjectName,
      groupName: groupName,
      teacher: teacher,
      semester: semester,
      type: type,
      year: year,
      controlPoints: controlPoints,
      students: students,
    );
  }

  static String _textById(dom.Document doc, String id) {
    // Ищем любой элемент с этим id (span, a, td, div — что угодно)
    final el = doc.querySelector('[id\$="$id"]');
    return el?.text.trim() ?? '';
  }

  // ─── Контрольные точки ───

  static List<ControlPoint> _parseControlPoints(_TableGrid sheet) {
    final pointRow = sheet.findRow(
      (row) =>
          row.any((text) => RegExp(r'^точка\s*\d+$').hasMatch(_norm(text))),
    );
    if (pointRow < 0) return const <ControlPoint>[];

    // Начала блоков: «Точка 1» занимает две колонки, поэтому берём первое
    // вхождение текста, а повторы справа пропускаем.
    final starts = <int>[];
    final names = <String>[];
    for (var col = 0; col < sheet.colCount; col++) {
      final text = sheet.cell(pointRow, col);
      if (!RegExp(r'^точка\s*\d+$').hasMatch(_norm(text))) continue;
      if (col > 0 && sheet.cell(pointRow, col - 1) == text) continue;
      starts.add(col);
      names.add(text);
    }
    if (starts.isEmpty) return const <ControlPoint>[];

    final weightLabelRow = sheet.findRow(
      (row) => row.any((text) => _norm(text).startsWith('весточки')),
    );
    // Строка подзаголовков «Лек. / Пр. / Лаб. / Др.» — их минимум четыре.
    final subHeaderRow = sheet.findRow((row) {
      var count = 0;
      for (final text in row) {
        final key = _norm(text);
        if (key.startsWith('лек') ||
            key.startsWith('лаб') ||
            key.startsWith('др') ||
            key == 'пр' ||
            key == 'пр.') {
          count++;
        }
      }
      return count >= 4;
    });
    // Веса — строка сразу под подзаголовками.
    var weightsRow = subHeaderRow < 0 ? -1 : subHeaderRow + 1;
    if (!_looksLikePercentRow(sheet, weightsRow)) {
      weightsRow = -1;
      for (
        var r = (subHeaderRow < 0 ? 0 : subHeaderRow + 1);
        r < sheet.rowCount;
        r++
      ) {
        if (_looksLikePercentRow(sheet, r)) {
          weightsRow = r;
          break;
        }
      }
    }

    final points = <ControlPoint>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final date = sheet.cell(pointRow, start + 2);
      final percent = _parsePercent(
        weightLabelRow < 0 ? '' : sheet.cell(weightLabelRow, start + 2),
      );
      final weights = <int>[];
      for (var k = 0; k < 4; k++) {
        weights.add(
          weightsRow < 0 ? 0 : _parsePercent(sheet.cell(weightsRow, start + k)),
        );
      }
      points.add(
        ControlPoint(
          name: names[i],
          date: date,
          weightPercent: percent,
          weights: weights,
        ),
      );
    }
    return points;
  }

  static bool _looksLikePercentRow(_TableGrid sheet, int row) {
    if (row < 0 || row >= sheet.rowCount) return false;
    var percents = 0;
    for (var col = 0; col < sheet.colCount; col++) {
      // Именно «50%», а не «Вес Точки,%» из строки выше.
      if (RegExp(r'^\d+\s*%$').hasMatch(sheet.cell(row, col).trim())) {
        percents++;
      }
    }
    return percents >= 4;
  }

  // ─── Строки студентов ───

  static List<StudentRow> _parseStudents(
    _TableGrid sheet,
    List<ControlPoint> points,
  ) {
    final recordBookCol = _findColumn(
      sheet,
      'номерзачетнойкнижки',
      fallback: 2,
    );
    final ratingCol = _findColumn(sheet, 'итоговыйрейтинг');
    final gradeCol = _findColumn(sheet, 'оценкапорейтингу');
    // В простой ведомости (экзамен/пересдача) оценка называется просто «Оценка».
    final simpleGradeCol = _findColumn(sheet, 'оценка', exact: true);
    final totalCol = _findColumn(sheet, 'итог', exact: true);

    final pointsStarts = _pointStarts(sheet);

    final students = <StudentRow>[];
    for (var row = 0; row < sheet.rowCount; row++) {
      if (!sheet.isStudentRow(row)) continue;

      final number = int.tryParse(_norm(sheet.cell(row, 0))) ?? 0;
      final recordBook = sheet.cell(row, recordBookCol).trim();
      if (recordBook.isEmpty) continue;

      final scores = <String>[];
      final ktTotals = <String>[];
      for (final start in pointsStarts) {
        for (var k = 0; k < 4; k++) {
          scores.add(sheet.cell(row, start + k).trim());
        }
        ktTotals.add(sheet.cell(row, start + 4).trim());
      }

      final finalRating = ratingCol < 0
          ? (totalCol < 0 ? '' : sheet.cell(row, totalCol).trim())
          : sheet.cell(row, ratingCol).trim();
      final grade = gradeCol >= 0
          ? sheet.cell(row, gradeCol).trim()
          : (simpleGradeCol >= 0 ? sheet.cell(row, simpleGradeCol).trim() : '');

      students.add(
        StudentRow(
          number: number,
          recordBook: recordBook,
          scores: scores,
          ktTotals: ktTotals,
          finalRating: finalRating,
          grade: grade,
        ),
      );
    }
    return students;
  }

  static List<int> _pointStarts(_TableGrid sheet) {
    final pointRow = sheet.findRow(
      (row) =>
          row.any((text) => RegExp(r'^точка\s*\d+$').hasMatch(_norm(text))),
    );
    if (pointRow < 0) return const <int>[];
    final starts = <int>[];
    for (var col = 0; col < sheet.colCount; col++) {
      final text = sheet.cell(pointRow, col);
      if (!RegExp(r'^точка\s*\d+$').hasMatch(_norm(text))) continue;
      if (col > 0 && sheet.cell(pointRow, col - 1) == text) continue;
      starts.add(col);
    }
    return starts;
  }

  /// Колонка по тексту заголовка (без учёта пробелов и регистра).
  static int _findColumn(
    _TableGrid sheet,
    String header, {
    bool exact = false,
    int fallback = -1,
  }) {
    final target = _norm(header);
    for (var row = 0; row < sheet.rowCount; row++) {
      if (sheet.isStudentRow(row)) continue;
      for (var col = 0; col < sheet.colCount; col++) {
        final text = _norm(sheet.cell(row, col));
        if (text.isEmpty) continue;
        if (exact ? text == target : text.startsWith(target)) {
          // Значение ищем в первой строке без объединения — это шапка.
          return col;
        }
      }
    }
    return fallback;
  }

  static int _parsePercent(String text) =>
      int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  static String _norm(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[\s\u00A0\u2007\u202F]+'), '');
}

/// Таблица ведомости, разложенная в сетку «строка → колонка → текст».
///
/// Нужна потому, что шапка использует colspan/rowspan: без учёта объединений
/// индексы ячеек в строке не совпадают с номерами колонок. Из-за этого
/// веса контрольных точек съезжали на одну точку вперёд.
class _TableGrid {
  _TableGrid(this._grid, this._studentRows, this.colCount);

  final List<List<String>> _grid;
  final Set<int> _studentRows;
  final int colCount;

  int get rowCount => _grid.length;

  String cell(int row, int col) {
    if (row < 0 || row >= _grid.length) return '';
    final line = _grid[row];
    if (col < 0 || col >= line.length) return '';
    return line[col];
  }

  bool isStudentRow(int row) => _studentRows.contains(row);

  int findRow(bool Function(List<String> row) test) {
    for (var row = 0; row < _grid.length; row++) {
      if (test(_grid[row])) return row;
    }
    return -1;
  }

  static _TableGrid fromTable(dom.Element table) {
    final rows = table.querySelectorAll('tr');
    final cells = <int, Map<int, String>>{};
    final studentRows = <int>{};
    var maxCol = 0;

    for (var r = 0; r < rows.length; r++) {
      final tr = rows[r];
      final rowClass = (tr.attributes['class'] ?? '').trim();
      final isStudent = rowClass == 'VedRow1' || rowClass == 'VedRow2';
      if (isStudent) studentRows.add(r);

      final rowCells = cells.putIfAbsent(r, () => <int, String>{});
      var col = 0;
      for (final cell in tr.querySelectorAll('th, td')) {
        while (rowCells.containsKey(col)) {
          col++;
        }
        final colspan = int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1;
        final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '1') ?? 1;
        final text = cell.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        for (var dr = 0; dr < rowspan; dr++) {
          for (var dc = 0; dc < colspan; dc++) {
            cells.putIfAbsent(r + dr, () => <int, String>{})[col + dc] = text;
          }
        }
        col += colspan;
        if (col > maxCol) maxCol = col;
      }
    }

    final grid = <List<String>>[];
    for (var r = 0; r < rows.length; r++) {
      final rowCells = cells[r] ?? const <int, String>{};
      var width = maxCol;
      for (final key in rowCells.keys) {
        if (key + 1 > width) width = key + 1;
      }
      grid.add(List<String>.generate(width, (c) => rowCells[c] ?? ''));
    }

    // Страховка: если у строк нет класса, считаем строками студентов те,
    // где первая ячейка — номер, а есть колонка с номером зачётки.
    if (studentRows.isEmpty) {
      for (var r = 0; r < grid.length; r++) {
        if (RegExp(r'^\d+$')
            .hasMatch(_normText(grid[r].isEmpty ? '' : grid[r][0]))) {
          studentRows.add(r);
        }
      }
    }

    return _TableGrid(grid, studentRows, maxCol);
  }

  static String _normText(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[\s\u00A0\u2007\u202F]+'), '');
}
