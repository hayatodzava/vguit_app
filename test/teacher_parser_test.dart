import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/teacher_schedule.dart';
import 'package:vguit_app/services/teacher_parser.dart';

/// Ячейка сайта выглядит так: тип, название предмета, ссылка с ФИО,
/// аудитория в скобках и группы после «гр.».
String cell(
  String type,
  String subject,
  String teacher,
  String room,
  List<String> groups,
) =>
    '''
<td>
  $type: $subject
  <a href="https://vsuet.ru/teacher"><div class="box_rounded link_prepod px-3">$teacher</div></a>
  (а.$room), ${groups.map((g) => 'гр.$g').join(', ')}
</td>''';

String row({
  required String day,
  required String time,
  required String week,
  required String cellHtml,
}) =>
    '''
<table class="table">
  <tr>
    <th><div class="vertical">$day</div></th>
    <th>$time</th>
    <th>$week</th>
    $cellHtml
  </tr>
</table>''';

String schedule(List<String> rows) =>
    '<html><body><div class="row my-3">${rows.join()}</div></body></html>';

void main() {
  group('название предмета', () {
    test('ФИО из ссылки не попадает в предмет', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell(
              'лекция',
              'Математический анализ',
              'Ощепкова С.Н.',
              '202',
              ['У-263'],
            ),
          ),
        ]),
      );

      expect(lessons, hasLength(1));
      expect(lessons.single.subject, 'Математический анализ');
      expect(lessons.single.type, 'лекция');
      expect(lessons.single.room, '202');
      expect(lessons.single.groups, ['У-263']);
    });

    test('ФИО без ссылки тоже отрезается', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'СРЕДА',
            time: '10.00-11.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: '<td>практика: Физика Иванов И.И. (а.310), гр.У-261</td>',
          ),
        ]),
      );

      expect(lessons.single.subject, 'Физика');
    });

    test('аудитория распознаётся с пробелом после «а.»', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ЧЕТВЕРГ',
            time: '14.00-15.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell(
              'лабораторные занятия',
              'Информатика',
              'Сидоров С.С.',
              ' 305 ',
              ['У-261'],
            ),
          ),
        ]),
      );

      expect(lessons.single.room, '305');
    });
  });

  group('склейка числителя и знаменателя', () {
    String pair({
      String subject = 'Математический анализ',
      String room = '202',
      List<String> numGroups = const ['У-263'],
      List<String> denGroups = const ['У-263'],
    }) => schedule([
      row(
        day: 'ПОНЕДЕЛЬНИК',
        time: '08.00-09.35',
        week: TeacherLesson.weekNumerator,
        cellHtml: cell('лекция', subject, 'Ощепкова С.Н.', room, numGroups),
      ),
      row(
        day: 'ПОНЕДЕЛЬНИК',
        time: '08.00-09.35',
        week: TeacherLesson.weekDenominator,
        cellHtml: cell('лекция', subject, 'Ощепкова С.Н.', room, denGroups),
      ),
    ]);

    test('одинаковые пары становятся одной карточкой', () {
      final lessons = TeacherParser.parseSchedule(pair());

      expect(lessons, hasLength(1));
      expect(lessons.single.week, TeacherLesson.weekBoth);
      expect(lessons.single.hasBothWeeks, isTrue);
    });

    test('порядок групп не мешает склейке', () {
      final lessons = TeacherParser.parseSchedule(
        pair(
          numGroups: const ['У-261', 'У-262'],
          denGroups: const ['У-262', 'У-261'],
        ),
      );

      expect(lessons, hasLength(1));
      expect(lessons.single.week, TeacherLesson.weekBoth);
      expect(lessons.single.groups, ['У-261', 'У-262']);
    });

    test('разные предметы не склеиваются', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'СРЕДА',
            time: '12.00-13.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Химия', 'Петров П.П.', '101', ['У-261']),
          ),
          row(
            day: 'СРЕДА',
            time: '12.00-13.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell('лекция', 'История', 'Петров П.П.', '101', [
              'У-261',
            ]),
          ),
        ]),
      );

      expect(lessons, hasLength(2));
      expect(lessons.map((l) => l.subject), ['Химия', 'История']);
      expect(lessons.every((l) => !l.hasBothWeeks), isTrue);
    });

    test('одна пара у нескольких групп — группы в одной карточке', () {
      // На сайте такая пара приходит отдельной строкой на каждую группу,
      // причём порядок строк и групп может быть любым.
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell(
              'лекция',
              'Общественный проект',
              'Иванов И.И.',
              '30',
              ['М-255'],
            ),
          ),
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell(
              'лекция',
              'Общественный проект',
              'Иванов И.И.',
              '30',
              ['М-256', 'М-254'],
            ),
          ),
        ]),
      );

      expect(lessons, hasLength(1));
      expect(lessons.single.groups, ['М-255', 'М-256', 'М-254']);
    });

    test('одна пара у нескольких групп на обеих неделях — одна карточка', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Проект', 'Иванов И.И.', '30', ['М-255']),
          ),
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Проект', 'Иванов И.И.', '30', ['М-256']),
          ),
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell('лекция', 'Проект', 'Иванов И.И.', '30', ['М-255']),
          ),
          row(
            day: 'ВТОРНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell('лекция', 'Проект', 'Иванов И.И.', '30', ['М-256']),
          ),
        ]),
      );

      expect(lessons, hasLength(1));
      expect(lessons.single.week, TeacherLesson.weekBoth);
      expect(lessons.single.groups, ['М-255', 'М-256']);
    });

    test('разные группы по неделям не склеиваются, но идут рядом', () {
      final lessons = TeacherParser.parseSchedule(
        pair(numGroups: const ['У-261'], denGroups: const ['У-262']),
      );

      expect(lessons, hasLength(2));

      final slots = groupIntoSlots(lessons);
      expect(slots, hasLength(1));
      expect(slots.single.hasSeveral, isTrue);
      expect(slots.single.lessons.map((l) => l.week), [
        TeacherLesson.weekNumerator,
        TeacherLesson.weekDenominator,
      ]);
    });

    test('разные аудитории не склеиваются', () {
      final lessons = TeacherParser.parseSchedule(pair(room: '202'));
      expect(lessons, hasLength(1));

      final different = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell(
              'лекция',
              'Математический анализ',
              'Ощепкова С.Н.',
              '202',
              ['У-263'],
            ),
          ),
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell(
              'лекция',
              'Математический анализ',
              'Ощепкова С.Н.',
              '203',
              ['У-263'],
            ),
          ),
        ]),
      );
      expect(different, hasLength(2));
    });

    test('только числитель остаётся одной карточкой', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ПЯТНИЦА',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Химия', 'Петров П.П.', '101', ['У-261']),
          ),
        ]),
      );

      expect(lessons.single.week, TeacherLesson.weekNumerator);
      expect(lessons.single.hasBothWeeks, isFalse);
    });
  });

  test('список преподавателей читается из select', () {
    const html = '''
<select name="select_prepod">
  <option value="">—</option>
  <option value="1">Алексеев М.В.</option>
  <option value="2">Агаева Н.Ю.</option>
</select>''';

    expect(TeacherParser.parseTeachers(html), ['Алексеев М.В.', 'Агаева Н.Ю.']);
  });

  group('слоты «день + время»', () {
    test('разные предметы числителя и знаменателя — один слот, две пары', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'СРЕДА',
            time: '12.00-13.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Химия', 'Петров П.П.', '101', ['У-261']),
          ),
          row(
            day: 'СРЕДА',
            time: '12.00-13.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell('лекция', 'История', 'Петров П.П.', '101', [
              'У-261',
            ]),
          ),
        ]),
      );

      expect(lessons, hasLength(2));

      final slots = groupIntoSlots(lessons);
      expect(slots, hasLength(1));
      expect(slots.single.hasSeveral, isTrue);
      // Внутри карточки порядок: сначала числитель, потом знаменатель.
      expect(slots.single.lessons.map((l) => l.subject), ['Химия', 'История']);
      expect(slots.single.lessons.map((l) => l.week), [
        TeacherLesson.weekNumerator,
        TeacherLesson.weekDenominator,
      ]);
    });

    test('одинаковая пара на обе недели — слот с одной парой', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Математика', 'Иванов И.И.', '202', [
              'У-1',
            ]),
          ),
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekDenominator,
            cellHtml: cell('лекция', 'Математика', 'Иванов И.И.', '202', [
              'У-1',
            ]),
          ),
        ]),
      );

      final slots = groupIntoSlots(lessons);
      expect(slots, hasLength(1));
      expect(slots.single.hasSeveral, isFalse);
      expect(slots.single.lessons.single.week, TeacherLesson.weekBoth);
    });

    test('разные пары в разное время — разные слоты', () {
      final lessons = TeacherParser.parseSchedule(
        schedule([
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '08.00-09.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Математика', 'Иванов И.И.', '202', [
              'У-1',
            ]),
          ),
          row(
            day: 'ПОНЕДЕЛЬНИК',
            time: '10.00-11.35',
            week: TeacherLesson.weekNumerator,
            cellHtml: cell('лекция', 'Физика', 'Иванов И.И.', '202', ['У-1']),
          ),
        ]),
      );

      final slots = groupIntoSlots(lessons);
      expect(slots, hasLength(2));
      expect(slots.map((s) => s.time), ['08.00-09.35', '10.00-11.35']);
    });
  });
}
