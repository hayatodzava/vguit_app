import 'dart:convert';

import '../models/teacher_schedule.dart';
import 'cache/cache_store.dart';
import 'net.dart';
import 'teacher_parser.dart';

class TeacherService {
  const TeacherService();

  static const String _url = 'https://timetable.vsuet.ru/index.php';
  static const CacheStore _store = CacheStore(CacheSection.teachersSchedule);

  Future<List<String>> fetchTeachers() async {
    final html = await _post(
      <String, String>{},
      action: 'Загрузка списка преподавателей',
    );
    final teachers = TeacherParser.parseTeachers(html);
    if (teachers.isEmpty) {
      throw AppException.parse(
        'На сайте расписания не найден список преподавателей — '
        'возможно, изменился адрес или вёрстка страницы.',
      );
    }
    return teachers;
  }

  Future<List<TeacherLesson>> fetchSchedule(String teacherName) async {
    final html = await _post(<String, String>{
      'select_prepod': teacherName,
    }, action: 'Загрузка расписания преподавателя');
    return TeacherParser.parseSchedule(html);
  }

  Future<String> _post(
    Map<String, String> extra, {
    required String action,
  }) async {
    final body = <String, String>{
      'select_prepod': '',
      'select_group': '',
      'select_aud': '',
      'select_week': '',
      'select_class': '',
      'select_dow': '',
      ...extra,
    };
    final response = await httpPost(
      Uri.parse(_url),
      headers: <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
            'Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,'
            'image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      },
      body: body,
      action: action,
    );
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  // ─── Кэш ───

  Future<List<String>?> loadTeachersFromCache() async {
    final raw = await _store.readJson('list');
    if (raw is! List) return null;
    try {
      return raw.map((item) => item.toString()).toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTeachersToCache(List<String> list) async {
    await _store.writeJson('list', list);
    await _store.writeTimestamp('list', DateTime.now());
  }

  Future<DateTime?> loadTeachersUpdatedAt() => _store.readTimestamp('list');

  /// Версия формата кэша расписаний.
  ///
  /// Меняется при правках парсера: иначе пользователь увидит старые данные
  /// (например, с ФИО в названии предмета) до ручной очистки кэша.
  static const int _cacheVersion = 3;

  Future<List<TeacherLesson>?> loadScheduleFromCache(String teacher) async {
    final raw = await _store.readJson('schedule_$teacher');
    if (raw is! Map) return null;
    if ((raw['version'] as num?)?.toInt() != _cacheVersion) return null;

    final lessons = raw['lessons'];
    if (lessons is! List) return null;
    try {
      return lessons
          .map((item) => _lessonFromJson(item as Map<dynamic, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveScheduleToCache(
    String teacher,
    List<TeacherLesson> list,
  ) async {
    await _store.writeJson('schedule_$teacher', {
      'version': _cacheVersion,
      'lessons': list.map(_lessonToJson).toList(growable: false),
    });
    await _store.writeTimestamp('schedule_$teacher', DateTime.now());
  }

  Future<DateTime?> loadUpdatedAt(String teacher) =>
      _store.readTimestamp('schedule_$teacher');

  // Полная очистка кэша преподавателей делается из настроек
  // (CacheManager по разделу), а не отсюда: обновление на экране
  // не должно стирать данные до успешного скачивания.

  static Map<String, Object?> _lessonToJson(TeacherLesson lesson) => {
    'day': lesson.day,
    'time': lesson.time,
    'week': lesson.week,
    'type': lesson.type,
    'subject': lesson.subject,
    'room': lesson.room,
    'groups': lesson.groups,
  };

  static TeacherLesson _lessonFromJson(Map<dynamic, dynamic> json) =>
      TeacherLesson(
        day: json['day'] as String? ?? '',
        time: json['time'] as String? ?? '',
        week: json['week'] as String? ?? '',
        type: json['type'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        room: json['room'] as String? ?? '',
        groups:
            (json['groups'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[],
      );
}
