import 'package:html/parser.dart' as html_parser;

import '../models/teacher_schedule.dart';

class TeacherParser {
  /// Парсит список преподавателей из <select name="select_prepod">.
  ///
  /// Первый пункт списка на сайте — заглушка («—») с пустым `value`:
  /// его пропускаем, иначе в выборе появляется пустая строка.
  static List<String> parseTeachers(String html) {
    final doc = html_parser.parse(html);
    final select = doc.querySelector('select[name="select_prepod"]');
    if (select == null) return [];
    return select
        .querySelectorAll('option')
        .where((option) => (option.attributes['value'] ?? '').isNotEmpty)
        .map((o) => o.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Парсит расписание из <div class="row my-3">.
  ///
  /// В ячейке сайт отдаёт: «лекция: Название предмета <a>Фамилия И.О.</a>
  /// (а.328), гр.М-260». Ссылку с ФИО убираем до разбора текста, поэтому
  /// в названии предмета остаётся только сам предмет.
  static List<TeacherLesson> parseSchedule(String html) {
    final doc = html_parser.parse(html);
    final container = doc.querySelector('div.row.my-3');
    if (container == null) return [];

    final rawLessons = <TeacherLesson>[];

    for (final table in container.querySelectorAll('table.table')) {
      final tr = table.querySelector('tr');
      if (tr == null) continue;

      final ths = tr.querySelectorAll('th');
      final tds = tr.querySelectorAll('td');
      if (ths.length < 3 || tds.isEmpty) continue;

      // День недели (в первой колонке текст повёрнут через div.vertical).
      final dayEl = ths[0].querySelector('div.vertical');
      final day = _normalize(dayEl?.text ?? ths[0].text);

      final time = _normalize(ths[1].text);
      final week = _normalize(ths[2].text);

      // Текст без ссылок на преподавателя и без кнопок.
      final cell = tds[0].clone(true);
      for (final element in cell.querySelectorAll('a, div.link_prepod')) {
        element.remove();
      }
      final text = _normalize(cell.text);

      final lesson = _parseCell(day: day, time: time, week: week, text: text);
      if (lesson == null) continue;
      rawLessons.add(lesson);
    }

    return _mergeLessons(rawLessons);
  }

  /// Разбирает текст ячейки: тип занятия, предмет, аудитория, группы.
  static TeacherLesson? _parseCell({
    required String day,
    required String time,
    required String week,
    required String text,
  }) {
    if (text.isEmpty) return null;

    var type = '';
    var rest = text;

    final colon = text.indexOf(':');
    if (colon > 0) {
      type = text.substring(0, colon).trim();
      rest = text.substring(colon + 1).trim();
    }

    // Аудитория — в скобках: (а.328) или (а. 328).
    var room = '';
    final roomMatch = RegExp(r'\(\s*а\.\s*([^)]+)\)').firstMatch(rest);
    if (roomMatch != null) {
      room = roomMatch.group(1)!.trim();
      rest = rest.replaceFirst(roomMatch.group(0)!, ' ');
    }

    // Группы — после «гр.», могут идти списком в любом порядке.
    final groups = <String>[];
    for (final match in RegExp(r'гр\.\s*([^\s,;]+)').allMatches(rest)) {
      final group = match.group(1)!.trim();
      if (group.isNotEmpty && !groups.contains(group)) groups.add(group);
    }
    rest = rest.replaceAll(RegExp(r'гр\.\s*[^\s,;]+'), ' ');

    // Осталось название предмета. Хвостовые «,» и пробелы от «гр.…»
    // убираем до отсечения ФИО, иначе якорь `$` в шаблоне не сработает.
    var subject = _normalize(rest);
    subject = subject.replaceAll(RegExp(r'[\s,;]+$'), '');
    subject = _stripTrailingName(subject);
    subject = subject.replaceAll(RegExp(r'[\s,;]+$'), '').trim();

    if (subject.isEmpty && groups.isEmpty) return null;

    return TeacherLesson(
      day: day,
      time: time,
      week: week,
      type: type,
      subject: subject,
      room: room,
      groups: List<String>.unmodifiable(groups),
    );
  }

  /// Страховка: если ФИО осталось текстом (например, ссылки на сайте нет).
  static String _stripTrailingName(String text) => text.replaceFirst(
    RegExp(r'\s+[А-ЯЁ][а-яё\-]+\s+[А-ЯЁ]\.\s*(?:[А-ЯЁ]\.)?$'),
    '',
  );

  static String _normalize(String text) => text
      .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<TeacherLesson> _mergeLessons(List<TeacherLesson> raw) {
    // 1. Одна и та же пара у нескольких групп: день, время, неделя, тип,
    //    предмет и аудитория совпадают, а группы идут отдельными строками
    //    (или в разном порядке). Группы собираем в один список.
    final collapsed = <TeacherLesson>[];
    for (final lesson in raw) {
      final index = collapsed.indexWhere(
        (existing) => existing.sameSlot(lesson) && existing.week == lesson.week,
      );
      if (index >= 0) {
        collapsed[index] = collapsed[index].copyWith(
          groups: _unionGroups(collapsed[index].groups, lesson.groups),
        );
      } else {
        collapsed.add(lesson);
      }
    }

    // 2. Числитель и знаменатель с полностью одинаковым содержимым
    //    (предмет, аудитория, группы) — одна карточка «обе недели».
    //    Если предметы или группы различаются, записи остаются разными,
    //    но попадут в общий слот и будут показаны рядом.
    final used = List<bool>.filled(collapsed.length, false);
    final result = <TeacherLesson>[];
    for (var i = 0; i < collapsed.length; i++) {
      if (used[i]) continue;
      final lesson = collapsed[i];

      if (lesson.week == TeacherLesson.weekNumerator) {
        final partner = _findPartner(collapsed, used, i, lesson);
        if (partner >= 0) {
          used[partner] = true;
          result.add(
            collapsed[i].copyWith(
              week: TeacherLesson.weekBoth,
              groups: _unionGroups(lesson.groups, collapsed[partner].groups),
            ),
          );
          used[i] = true;
          continue;
        }
      }

      result.add(lesson);
      used[i] = true;
    }
    return result;
  }

  /// Ищет пару «знаменатель» к строке «числитель».
  static int _findPartner(
    List<TeacherLesson> lessons,
    List<bool> used,
    int current,
    TeacherLesson lesson,
  ) {
    for (var j = 0; j < lessons.length; j++) {
      if (j == current || used[j]) continue;
      final other = lessons[j];
      if (other.week != TeacherLesson.weekDenominator) continue;
      if (!other.sameSlot(lesson)) continue;
      if (!other.hasSameGroups(lesson)) continue;
      return j;
    }
    return -1;
  }

  /// Объединение групп с сохранением порядка первого списка.
  static List<String> _unionGroups(List<String> first, List<String> second) {
    final merged = <String>[...first];
    for (final group in second) {
      if (!merged.contains(group)) merged.add(group);
    }
    return List<String>.unmodifiable(merged);
  }
}
