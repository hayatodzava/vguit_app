import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vguit_app/services/schedule_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('расписание студентов', () {
    test('курс и группа сохраняются и читаются', () async {
      const prefs = SchedulePreferences();
      await prefs.saveStudents(course: '2 курс', group: 'У-261');

      expect(await prefs.loadCourse(), '2 курс');
      expect(await prefs.loadGroup(), 'У-261');
    });

    test('«все группы» очищает сохранённую группу', () async {
      const prefs = SchedulePreferences();
      await prefs.saveStudents(course: '2 курс', group: 'У-261');
      await prefs.saveStudents(course: '2 курс', group: null);

      expect(await prefs.loadGroup(), isNull);
      expect(await prefs.loadCourse(), '2 курс');
    });

    test('без сохранений возвращается null', () async {
      const prefs = SchedulePreferences();
      expect(await prefs.loadCourse(), isNull);
      expect(await prefs.loadGroup(), isNull);
    });
  });

  group('расписание преподавателей', () {
    test('преподаватель и день сохраняются', () async {
      const prefs = SchedulePreferences();
      await prefs.saveTeacher(teacher: 'Иванов И.И.', day: 'ВТОРНИК');

      expect(await prefs.loadTeacher(), 'Иванов И.И.');
      expect(await prefs.loadTeacherDay(), 'ВТОРНИК');
    });

    test('«все дни» очищает сохранённый день', () async {
      const prefs = SchedulePreferences();
      await prefs.saveTeacher(teacher: 'Иванов И.И.', day: 'ВТОРНИК');
      await prefs.saveTeacher(teacher: 'Иванов И.И.', day: null);

      expect(await prefs.loadTeacherDay(), isNull);
      expect(await prefs.loadTeacher(), 'Иванов И.И.');
    });

    test('пустое имя преподавателя не сохраняется', () async {
      const prefs = SchedulePreferences();
      await prefs.saveTeacher(teacher: '', day: 'СРЕДА');

      expect(await prefs.loadTeacher(), isNull);
      expect(await prefs.loadTeacherDay(), 'СРЕДА');
    });
  });
}
