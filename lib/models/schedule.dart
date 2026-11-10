class ScheduleData {
  final String faculty;
  final String course;
  final List<String> groups;
  final List<GroupInfo> groupCols;
  final List<String> timeSlots;
  final Map<String, Map<String, Map<String, LessonCell>>> lessons;

  ScheduleData({
    required this.faculty,
    required this.course,
    required this.groups,
    required this.groupCols,
    required this.timeSlots,
    required this.lessons,
  });
}

class GroupInfo {
  final String name;
  final bool hasSubgroups;
  GroupInfo({required this.name, required this.hasSubgroups});
}

class LessonCell {
  final String numerator; // числитель (1-я неделя)
  final String denominator; // знаменатель (2-я неделя)
  final String sub1Num;
  final String sub1Den;
  final String sub2Num;
  final String sub2Den;
  final bool hasSubgroups;

  LessonCell({
    this.numerator = '',
    this.denominator = '',
    this.sub1Num = '',
    this.sub1Den = '',
    this.sub2Num = '',
    this.sub2Den = '',
    this.hasSubgroups = false,
  });

  bool get isEmpty {
    if (hasSubgroups) {
      return sub1Num.isEmpty &&
          sub1Den.isEmpty &&
          sub2Num.isEmpty &&
          sub2Den.isEmpty;
    }
    return numerator.isEmpty && denominator.isEmpty;
  }

  bool get hasTwoWeeks {
    if (hasSubgroups) {
      return sub1Den.isNotEmpty || sub2Den.isNotEmpty;
    }
    return denominator.isNotEmpty;
  }
}
