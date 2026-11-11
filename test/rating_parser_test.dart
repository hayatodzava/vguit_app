import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/services/rating_parser.dart';

/// Собирает страницу ведомости с контрольными точками.
///
/// Структура повторяет сайт: блок точки занимает 5 колонок — «Точка N»
/// (colspan 2), дата (colspan 2) и «Итог по КТ N» (rowspan 4). Именно из-за
/// этих объединений старый парсер съезжал на одну точку вперёд.
String ratingPage({
  required List<String> dates,
  required List<int> percents,
  required List<List<int>> weights,
  required List<List<String>> ktTotals,
  required List<List<String>> scores,
  String rating = '18',
  String grade = 'Неуд',
  String total = 'Незачет',
}) {
  final buffer = StringBuffer()
    ..writeln('<html><body>')
    ..writeln('<span id="cph_ucVedBox_lblGroup">У-253</span>')
    ..writeln('<span id="cph_ucVedBox_lblPrep">Иванов И.И.</span>')
    ..writeln('<span id="cph_ucVedBox_lblSem">Осень</span>')
    ..writeln('<span id="cph_ucVedBox_lblTypeVed">Зачет</span>')
    ..writeln('<span id="cph_ucVedBox_lblYear">2026-2027</span>')
    ..writeln('<span id="cph_ucVedBox_lblDis">Методы оптимизации</span>')
    ..writeln('<table id="cph_ucVedBox_tblVed"><tr id="cph_ucVedBox_Row1">')
    ..writeln('<td rowspan="4">№</td><td rowspan="4">ФИО</td>')
    ..writeln('<td rowspan="4">Номер зачетной книжки</td>');

  for (var i = 0; i < dates.length; i++) {
    buffer
      ..writeln('<td colspan="2">Точка ${i + 1}</td>')
      ..writeln('<td class="VedRow1" colspan="2">${dates[i]}</td>')
      ..writeln('<td rowspan="4">Итог по КТ ${i + 1}</td>');
  }
  buffer
    ..writeln('<td rowspan="4">Над бав ка %</td>')
    ..writeln('<td rowspan="4">Итоговый Рейтинг</td>')
    ..writeln('<td rowspan="4">Оценка по рейтингу</td>')
    ..writeln('<td class="VedRow1">18.01.2027</td>')
    ..writeln('<td rowspan="4">Итог</td>')
    ..writeln('<td rowspan="4">Подпись</td>')
    ..writeln('<td rowspan="4">№</td>')
    ..writeln('<td rowspan="4"></td>')
    ..writeln('</tr><tr>');
  for (var i = 0; i < dates.length; i++) {
    buffer
      ..writeln('<td colspan="2">Вес Точки,%</td>')
      ..writeln('<td colspan="2">${percents[i]}%</td>');
  }
  buffer
    ..writeln('<td rowspan="3">Зачет</td>')
    ..writeln('</tr><tr>');
  for (var i = 0; i < dates.length; i++) {
    buffer.writeln('<td>Лек.</td><td>Пр.</td><td>Лаб.</td><td>Др.</td>');
  }
  buffer.writeln('</tr><tr>');
  for (var i = 0; i < dates.length; i++) {
    for (final weight in weights[i]) {
      buffer.writeln('<td>$weight%</td>');
    }
  }
  buffer.writeln('</tr>');

  for (var student = 0; student < scores.length; student++) {
    buffer
      ..writeln('<tr class="VedRow${student.isEven ? 1 : 2}">')
      ..writeln('<td><a>${student + 1}</a></td><td>${student + 1}</td>')
      ..writeln('<td>${257049 + student}</td>');
    for (var point = 0; point < dates.length; point++) {
      for (var part = 0; part < 4; part++) {
        buffer.writeln('<td>${scores[student][point * 4 + part]}</td>');
      }
      buffer.writeln('<td>${ktTotals[student][point]}</td>');
    }
    buffer
      ..writeln('<td></td><td>$rating</td><td>$grade</td><td></td>')
      ..writeln('<td>$total</td><td></td><td>${student + 1}</td><td></td>')
      ..writeln('</tr>');
  }
  buffer.writeln('</table></body></html>');
  return buffer.toString();
}

/// Простая ведомость экзамена: ФИО, дата сдачи, оценка, пересдачи.
String examPage() => '''
<html><body>
<span id="cph_ucVedBox_lblGroup">ЗИВ-26</span>
<span id="cph_ucVedBox_lblDis">Алгоритмы и структуры данных</span>
<span id="cph_ucVedBox_lblTypeVed">Экзамен</span>
<table id="cph_ucVedBox_tblVed">
  <tr>
    <td>?</td><td>ФИО</td><td>Номер зачетной книжки</td>
    <td>Дата сдачи</td><td>Оценка</td><td>Подпись</td>
    <td colspan="2">Первая пересдача</td>
    <td colspan="2">Вторая пересдача</td>
    <td colspan="2">Третья пересдача</td>
    <td>?</td><td></td>
  </tr>
  <tr>
    <td>Дата</td><td>Результат</td><td>Дата</td><td>Результат</td>
    <td>Дата</td><td>Результат</td><td></td>
  </tr>
  <tr><td></td></tr>
  <tr><td></td></tr>
  <tr class="VedRow1">
    <td><a>1</a></td><td>Иванов И.И.</td><td>267415</td>
    <td>12.01.2026</td><td>Отл</td><td></td>
    <td></td><td></td><td></td><td></td><td></td><td></td>
    <td>1</td><td></td>
  </tr>
  <tr class="VedRow2">
    <td><a>2</a></td><td>Петров П.П.</td><td>267416</td>
    <td>12.01.2026</td><td>Неуд</td><td></td>
    <td></td><td></td><td></td><td></td><td></td><td></td>
    <td>2</td><td></td>
  </tr>
</table></body></html>
''';

void main() {
  group('ведомость с контрольными точками', () {
    test('веса каждой точки берутся из своей строки', () {
      final html = ratingPage(
        dates: [
          '28.09.2026',
          '28.10.2026',
          '28.11.2026',
          '28.12.2026',
          '28.01.2027',
        ],
        percents: [10, 20, 15, 25, 30],
        weights: [
          [40, 60, 0, 0],
          [0, 100, 0, 0],
          [100, 0, 0, 0],
          [50, 50, 0, 0],
          [0, 0, 100, 0],
        ],
        ktTotals: [
          ['79', '', '', '', ''],
        ],
        scores: [
          [
            '85',
            '75',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
        ],
      );

      final vedomost = RatingParser.parseVedomost(html, '1');
      expect(vedomost.controlPoints, hasLength(5));

      final expectedWeights = [
        [40, 60, 0, 0],
        [0, 100, 0, 0],
        [100, 0, 0, 0],
        [50, 50, 0, 0],
        [0, 0, 100, 0],
      ];
      final expectedPercents = [10, 20, 15, 25, 30];

      for (var i = 0; i < 5; i++) {
        final point = vedomost.controlPoints[i];
        expect(point.name, 'Точка ${i + 1}');
        expect(
          point.weights,
          expectedWeights[i],
          reason: 'веса точки ${i + 1}',
        );
        expect(
          point.weightPercent,
          expectedPercents[i],
          reason: 'вес точки ${i + 1}',
        );
        expect(point.weights.fold<int>(0, (a, b) => a + b), 100);
      }
    });

    test('пятая точка не остаётся без весов', () {
      final html = ratingPage(
        dates: ['1', '2', '3', '4', '5'],
        percents: [20, 20, 20, 20, 20],
        weights: [
          [100, 0, 0, 0],
          [100, 0, 0, 0],
          [100, 0, 0, 0],
          [100, 0, 0, 0],
          [100, 0, 0, 0],
        ],
        ktTotals: [
          ['', '', '', '', ''],
        ],
        scores: [List<String>.filled(20, '')],
      );

      final points = RatingParser.parseVedomost(html, '1').controlPoints;
      expect(points, hasLength(5));
      expect(points.last.weights, [100, 0, 0, 0]);
    });

    test('оценки и итоги по КТ читаются по своим колонкам', () {
      final html = ratingPage(
        dates: ['28.02.2026', '28.03.2026'],
        percents: [50, 50],
        weights: [
          [50, 0, 50, 0],
          [100, 0, 0, 0],
        ],
        ktTotals: [
          ['80', '10'],
          ['20', '5'],
        ],
        scores: [
          ['80', '', '80', '', '10', '', '', ''],
          ['20', '', '20', '', '5', '', '', ''],
        ],
        rating: '18',
        grade: 'Неуд',
      );

      final students = RatingParser.parseVedomost(html, '1').students;
      expect(students, hasLength(2));

      expect(students[0].number, 1);
      expect(students[0].recordBook, '257049');
      expect(students[0].scores, ['80', '', '80', '', '10', '', '', '']);
      expect(students[0].ktTotals, ['80', '10']);
      expect(students[0].finalRating, '18');
      expect(students[0].grade, 'Неуд');

      expect(students[1].recordBook, '257050');
      expect(students[1].ktTotals, ['20', '5']);
    });

    test('одна точка читается так же корректно', () {
      final html = ratingPage(
        dates: ['28.09.2026'],
        percents: [20],
        weights: [
          [40, 60, 0, 0],
        ],
        ktTotals: [
          ['79'],
        ],
        scores: [
          ['85', '75', '', ''],
        ],
      );

      final vedomost = RatingParser.parseVedomost(html, '1');
      expect(vedomost.controlPoints, hasLength(1));
      expect(vedomost.controlPoints.single.weights, [40, 60, 0, 0]);
      expect(vedomost.students.single.scores, ['85', '75', '', '']);
      expect(vedomost.students.single.ktTotals, ['79']);
    });

    test('шапка ведомости читается', () {
      final html = ratingPage(
        dates: ['1'],
        percents: [20],
        weights: [
          [100, 0, 0, 0],
        ],
        ktTotals: [
          [''],
        ],
        scores: [List<String>.filled(4, '')],
      );

      final vedomost = RatingParser.parseVedomost(html, '42');
      expect(vedomost.subjectId, '42');
      expect(vedomost.subjectName, 'Методы оптимизации');
      expect(vedomost.groupName, 'У-253');
      expect(vedomost.teacher, 'Иванов И.И.');
      expect(vedomost.type, 'Зачет');
    });
  });

  group('ведомость экзамена без контрольных точек', () {
    test('оценка берётся из колонки «Оценка»', () {
      final vedomost = RatingParser.parseVedomost(examPage(), '1');

      expect(vedomost.controlPoints, isEmpty);
      expect(vedomost.students, hasLength(2));

      expect(vedomost.students[0].number, 1);
      expect(vedomost.students[0].recordBook, '267415');
      expect(vedomost.students[0].grade, 'Отл');
      expect(vedomost.students[0].finalRating, isEmpty);

      expect(vedomost.students[1].grade, 'Неуд');
    });
  });
}
