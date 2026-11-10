/// Как часто проверять расписание.
enum ScheduleCheckFrequency {
  daily('Каждый день'),
  weekly('Раз в неделю');

  const ScheduleCheckFrequency(this.label);

  final String label;

  static ScheduleCheckFrequency fromName(String? name) {
    for (final value in ScheduleCheckFrequency.values) {
      if (value.name == name) return value;
    }
    return ScheduleCheckFrequency.daily;
  }
}

/// Настройки уведомлений об изменении расписания студентов.
class ScheduleNotificationSettings {
  const ScheduleNotificationSettings({
    this.enabled = false,
    this.frequency = ScheduleCheckFrequency.daily,
    this.weekday = DateTime.monday,
    this.hour = 8,
    this.minute = 0,
    this.faculty,
    this.groups = const <String>[],
  });

  /// Названия дней недели, индекс = `DateTime.weekday`.
  static const List<String> weekdayNames = <String>[
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  final bool enabled;

  final ScheduleCheckFrequency frequency;

  /// День недели для режима «раз в неделю» (1 — понедельник).
  final int weekday;

  final int hour;
  final int minute;

  /// Факультет, за которым следим (один).
  final String? faculty;

  /// Группы этого факультета (несколько).
  final List<String> groups;

  /// Настроено ли всё необходимое для фоновой проверки.
  bool get isComplete =>
      enabled && faculty != null && faculty!.isNotEmpty && groups.isNotEmpty;

  /// Подпись дня недели.
  String get weekdayLabel => weekdayName(weekday);

  static String weekdayName(int weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      return weekdayNames.first;
    }
    return weekdayNames[weekday - 1];
  }

  /// Время в формате ЧЧ:ММ.
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Расписание проверок: «Каждый день в 08:00».
  String get scheduleLabel => frequency == ScheduleCheckFrequency.daily
      ? '${frequency.label}, в $timeLabel'
      : '${frequency.label}, ${weekdayLabel.toLowerCase()}, в $timeLabel';

  /// Ближайший запуск строго после [now].
  DateTime nextRun(DateTime now) {
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (frequency == ScheduleCheckFrequency.daily) {
      if (!candidate.isAfter(now)) {
        candidate = DateTime(now.year, now.month, now.day + 1, hour, minute);
      }
      return candidate;
    }

    // Раз в неделю: ищем ближайший нужный день (не больше недели вперёд).
    for (var i = 0; i <= 7; i++) {
      final day = DateTime(now.year, now.month, now.day + i, hour, minute);
      if (day.weekday == weekday && day.isAfter(now)) return day;
    }
    return candidate;
  }

  ScheduleNotificationSettings copyWith({
    bool? enabled,
    ScheduleCheckFrequency? frequency,
    int? weekday,
    int? hour,
    int? minute,
    String? faculty,
    bool clearFaculty = false,
    List<String>? groups,
  }) {
    return ScheduleNotificationSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      weekday: weekday ?? this.weekday,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      faculty: clearFaculty ? null : (faculty ?? this.faculty),
      groups: groups ?? this.groups,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'frequency': frequency.name,
    'weekday': weekday,
    'hour': hour,
    'minute': minute,
    'faculty': faculty,
    'groups': groups,
  };

  factory ScheduleNotificationSettings.fromJson(Map<String, Object?> json) {
    return ScheduleNotificationSettings(
      enabled: json['enabled'] as bool? ?? false,
      frequency: ScheduleCheckFrequency.fromName(json['frequency'] as String?),
      weekday: (json['weekday'] as num?)?.toInt() ?? DateTime.monday,
      hour: (json['hour'] as num?)?.toInt() ?? 8,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      faculty: json['faculty'] as String?,
      groups:
          (json['groups'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
    );
  }

  @override
  String toString() =>
      'ScheduleNotificationSettings(enabled=$enabled, $scheduleLabel, '
      'faculty=$faculty, groups=${groups.length})';
}
