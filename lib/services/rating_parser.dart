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
  static Vedomost parseVedomost(String html, String subjectId) {
    final doc = html_parser.parse(html);

    // ── Шапка
    final groupName = _textById(doc, 'ucVedBox_lblGroup');
    final teacher = _textById(doc, 'ucVedBox_lblPrep');
    final semester = _textById(doc, 'ucVedBox_lblSem');
    final type = _textById(doc, 'ucVedBox_lblTypeVed');
    final year = _textById(doc, 'ucVedBox_lblYear');
    final subjectName = _textById(doc, 'ucVedBox_lblDis');

    // ── Точки КТ
    final controlPoints = _parseControlPoints(doc);

    // ── Строки студентов
    final students = _parseStudents(doc, controlPoints.length);

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

  /// Парсит шапку с КТ: names, dates, weights.
  static List<ControlPoint> _parseControlPoints(dom.Document doc) {
    final table = doc.querySelector('table[id\$="ucVedBox_tblVed"]');
    if (table == null) return [];

    final rows = table.querySelectorAll('tr');
    if (rows.length < 4) return [];

    // Строка 1: "Точка 1", date, "Итог по КТ 1", ...
    final row1 = rows[0].querySelectorAll('td');
    // Строка 2: "Вес Точки,%", "20%", ...
    final row2 = rows[1].querySelectorAll('td');
    // Строка 4: "100%", "0%", "0%", "0%", ...
    final row4 = rows[3].querySelectorAll('td');

    // Ищем "Точка N" в row1.
    final points = <ControlPoint>[];
    for (int i = 0; i < row1.length; i++) {
      final text = row1[i].text.trim();
      if (RegExp(r'^Точка\s+\d+$').hasMatch(text)) {
        // Следующая ячейка — дата
        final date = i + 1 < row1.length ? row1[i + 1].text.trim() : '';

        // Вес точки: в row2 ищем "NN%" рядом с "Вес Точки,%".
        // row2 имеет структуру: "Вес Точки,%", "20%", "Вес Точки,%", "20%", ...
        int weight = 0;
        for (int j = 0; j < row2.length; j++) {
          if (row2[j].text.trim().startsWith('Вес')) {
            if (j + 1 < row2.length) {
              final w = row2[j + 1].text.trim().replaceAll('%', '');
              weight = int.tryParse(w) ?? 0;
            }
            break;
          }
        }

        // Веса Лек/Пр/Лаб/Др: в row4 ищем 4 числа подряд, начиная
        // с позиции соответствующей точке. Точки идут каждые 4 ячейки.
        final pointIndex = points.length;
        final startIdx = 4 + pointIndex * 4; // 4 ячейки до первой точки
        final weights = <int>[];
        for (int k = 0; k < 4; k++) {
          if (startIdx + k < row4.length) {
            final v = row4[startIdx + k].text.trim().replaceAll('%', '');
            weights.add(int.tryParse(v) ?? 0);
          } else {
            weights.add(0);
          }
        }

        points.add(
          ControlPoint(
            name: text,
            date: date,
            weightPercent: weight,
            weights: weights,
          ),
        );
      }
    }
    return points;
  }

  /// Парсит строки студентов.
  static List<StudentRow> _parseStudents(dom.Document doc, int ktCount) {
    final table = doc.querySelector('table[id\$="ucVedBox_tblVed"]');
    if (table == null) return [];

    final result = <StudentRow>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cls = tr.attributes['class'] ?? '';
      if (cls != 'VedRow1' && cls != 'VedRow2') continue;

      final tds = tr.querySelectorAll('td');
      if (tds.length < 3) continue;

      final number = int.tryParse(tds[0].text.trim()) ?? 0;
      final recordBook = tds[2].text.trim();
      if (recordBook.isEmpty) continue;

      // Индекс текущей ячейки в tds
      int idx = 3;

      // Оценки по точкам
      final scores = <String>[];
      final ktTotals = <String>[];
      for (int kt = 0; kt < ktCount; kt++) {
        for (int j = 0; j < 4; j++) {
          scores.add(idx < tds.length ? tds[idx].text.trim() : '');
          idx++;
        }
        ktTotals.add(idx < tds.length ? tds[idx].text.trim() : '');
        idx++;
      }

      // После КТ: "Надбавка %", "Итоговый Рейтинг", "Оценка по рейтингу", ...
      // idx указывает на "Надбавка %" — пропускаем её
      String finalRating = '';
      String grade = '';
      if (idx < tds.length) {
        idx++; // надбавка
      }
      if (idx < tds.length) {
        finalRating = tds[idx].text.trim();
        idx++;
      }
      if (idx < tds.length) {
        grade = tds[idx].text.trim();
      }

      result.add(
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
    return result;
  }
}
