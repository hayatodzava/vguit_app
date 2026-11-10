class Faculty {
  final String id;
  final String name;
  const Faculty({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Faculty && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Group {
  final String id;
  final String name;
  const Group({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Subject {
  final String id;
  final String name;
  final String type;
  final bool closed;

  const Subject({
    required this.id,
    required this.name,
    required this.type,
    required this.closed,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subject && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Одна контрольная точка в шапке таблицы.
/// Например: "Точка 1" с датой, весом и распределением Лек/Пр/Лаб/Др.
class ControlPoint {
  final String name; // "Точка 1"
  final String date; // "28.09.2026"
  final int weightPercent; // 20
  final List<int> weights; // [40, 60, 0, 0] — Лек/Пр/Лаб/Др

  const ControlPoint({
    required this.name,
    required this.date,
    required this.weightPercent,
    required this.weights,
  });
}

/// Строка студента в ведомости.
class StudentRow {
  final int number;
  final String recordBook; // номер зачётки (257049)
  final List<String>
  scores; // все оценки по порядку (для Лек/Пр/Лаб/Др каждой точки)
  final List<String> ktTotals; // итоги по КТ
  final String finalRating; // итоговый рейтинг
  final String grade; // оценка

  const StudentRow({
    required this.number,
    required this.recordBook,
    required this.scores,
    required this.ktTotals,
    required this.finalRating,
    required this.grade,
  });
}

class Vedomost {
  final String subjectId;
  final String subjectName;
  final String groupName;
  final String teacher;
  final String semester;
  final String type; // Экзамен / Зачет
  final String year;
  final List<ControlPoint> controlPoints;
  final List<StudentRow> students;

  const Vedomost({
    required this.subjectId,
    required this.subjectName,
    required this.groupName,
    required this.teacher,
    required this.semester,
    required this.type,
    required this.year,
    required this.controlPoints,
    required this.students,
  });
}

/// Результат для "моей зачётки": по каждому предмету — оценка.
class MyScore {
  final Subject subject;
  final String totalRating; // итоговый рейтинг
  final String grade; // оценка
  final List<String> ktTotals; // итоги по каждой КТ

  const MyScore({
    required this.subject,
    required this.totalRating,
    required this.grade,
    required this.ktTotals,
  });
}
