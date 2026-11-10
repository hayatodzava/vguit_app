import 'package:shared_preferences/shared_preferences.dart';

/// Последний выбор на экранах расписания.
///
/// Хранится отдельно от кэша: очистка кэша расписания не должна сбрасывать
/// курс, группу и преподавателя, которые выбрал пользователь.
class SchedulePreferences {
  const SchedulePreferences();

  static const String _courseKey = 'schedule_students_course';
  static const String _groupKey = 'schedule_students_group';
  static const String _teacherKey = 'schedule_teacher_name';
  static const String _teacherDayKey = 'schedule_teacher_day';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ─── Расписание студентов ───

  Future<String?> loadCourse() async {
    final prefs = await _prefs;
    return prefs.getString(_courseKey);
  }

  Future<String?> loadGroup() async {
    final prefs = await _prefs;
    return prefs.getString(_groupKey);
  }

  /// Сохраняет курс и группу. `null` в группе — «все группы».
  Future<void> saveStudents({String? course, String? group}) async {
    final prefs = await _prefs;
    if (course != null && course.isNotEmpty) {
      await prefs.setString(_courseKey, course);
    }
    if (group == null || group.isEmpty) {
      await prefs.remove(_groupKey);
    } else {
      await prefs.setString(_groupKey, group);
    }
  }

  // ─── Расписание преподавателей ───

  Future<String?> loadTeacher() async {
    final prefs = await _prefs;
    return prefs.getString(_teacherKey);
  }

  Future<String?> loadTeacherDay() async {
    final prefs = await _prefs;
    return prefs.getString(_teacherDayKey);
  }

  /// Сохраняет преподавателя и выбранный день (`null` — все дни).
  Future<void> saveTeacher({String? teacher, String? day}) async {
    final prefs = await _prefs;
    if (teacher == null || teacher.isEmpty) {
      await prefs.remove(_teacherKey);
    } else {
      await prefs.setString(_teacherKey, teacher);
    }
    if (day == null || day.isEmpty) {
      await prefs.remove(_teacherDayKey);
    } else {
      await prefs.setString(_teacherDayKey, day);
    }
  }
}
