/// Одна пара в расписании преподавателя.
class TeacherLesson {
  TeacherLesson({
    required this.day,
    required this.time,
    required this.week,
    required this.type,
    required this.subject,
    required this.room,
    required this.groups,
  });

  /// Значения колонки «Неделя» на сайте.
  static const String weekNumerator = 'числитель';
  static const String weekDenominator = 'знаменатель';

  /// Пара идёт и в числитель, и в знаменатель — показывается одной карточкой.
  static const String weekBoth = 'числитель и знаменатель';

  final String day;
  final String time;
  final String week;
  final String type;
  final String subject;
  final String room;
  final List<String> groups;

  bool get hasBothWeeks => week == weekBoth;

  /// Группы без учёта порядка: на сайте они могут идти по-разному.
  Set<String> get groupSet => groups.toSet();

  bool hasSameGroups(TeacherLesson other) {
    final mine = groupSet;
    final theirs = other.groupSet;
    return mine.length == theirs.length && mine.containsAll(theirs);
  }

  /// Одна и та же пара: совпадает день, время, тип, предмет и аудитория.
  bool sameSlot(TeacherLesson other) =>
      day == other.day &&
      time == other.time &&
      type == other.type &&
      subject == other.subject &&
      room == other.room;

  /// Совпадают день и время — пары показываются одной карточкой.
  bool sameTime(TeacherLesson other) => day == other.day && time == other.time;

  TeacherLesson copyWith({String? week, List<String>? groups}) => TeacherLesson(
    day: day,
    time: time,
    week: week ?? this.week,
    type: type,
    subject: subject,
    room: room,
    groups: groups ?? this.groups,
  );

  TeacherLesson copyWithGroups(List<String> newGroups) =>
      copyWith(groups: newGroups);

  @override
  String toString() =>
      'TeacherLesson($day $time [$week] $type: $subject, а.$room, ${groups.join(", ")})';
}

/// Пара (или несколько пар) в одно и то же время одного дня.
///
/// Внутри слота может быть две разные пары: одна по числителю, другая
/// по знаменателю. Они не склеиваются в одну запись, но показываются
/// в общей карточке, чтобы недели читались рядом.
class TeacherSlot {
  TeacherSlot({
    required this.day,
    required this.time,
    required List<TeacherLesson> lessons,
  }) : lessons = List<TeacherLesson>.unmodifiable(lessons);

  final String day;
  final String time;
  final List<TeacherLesson> lessons;

  /// В слоте несколько разных пар (числитель/знаменатель).
  bool get hasSeveral => lessons.length > 1;

  @override
  String toString() => 'TeacherSlot($day $time: ${lessons.length} пар)';
}

/// Группирует пары в слоты «день + время», сохраняя порядок появления.
List<TeacherSlot> groupIntoSlots(Iterable<TeacherLesson> lessons) {
  final byKey = <String, List<TeacherLesson>>{};
  for (final lesson in lessons) {
    (byKey['${lesson.day}|${lesson.time}'] ??= <TeacherLesson>[]).add(lesson);
  }

  return <TeacherSlot>[
    for (final entry in byKey.values)
      TeacherSlot(
        day: entry.first.day,
        time: entry.first.time,
        lessons: entry..sort(_byWeek),
      ),
  ];
}

/// Порядок внутри карточки: числитель, знаменатель, обе недели, прочее.
int _byWeek(TeacherLesson a, TeacherLesson b) =>
    _weekRank(a.week).compareTo(_weekRank(b.week));

int _weekRank(String week) {
  switch (week) {
    case TeacherLesson.weekNumerator:
      return 0;
    case TeacherLesson.weekDenominator:
      return 1;
    case TeacherLesson.weekBoth:
      return 2;
    default:
      return 3;
  }
}
