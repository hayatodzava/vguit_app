import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../net.dart';

/// Разделы кэша. У каждого свой префикс ключей и своя строка в настройках,
/// поэтому их можно взвешивать и чистить по отдельности.
enum CacheSection {
  studentsSchedule(
    id: 'students_schedule',
    title: 'Расписание студентов',
    description: 'Скачанные файлы расписания факультетов',
    legacyPrefixes: <String>['schedule_xlsx'],
  ),
  teachersSchedule(
    id: 'teachers_schedule',
    title: 'Расписание преподавателей',
    description: 'Список преподавателей и их пары',
    legacyPrefixes: <String>['teacher'],
  ),
  rating(
    id: 'rating',
    title: 'Рейтинг',
    description: 'Факультеты, группы, предметы и ведомости',
    legacyPrefixes: <String>[
      'rating_faculties',
      'rating_groups_',
      'rating_subjects_',
      'rating_ved_',
      'rating_updated_at_',
    ],
  );

  const CacheSection({
    required this.id,
    required this.title,
    required this.description,
    required this.legacyPrefixes,
  });

  final String id;
  final String title;
  final String description;

  /// Префиксы ключей старого формата: их тоже учитываем в весе и удаляем,
  /// иначе после обновления приложения кэш «зависнет» навсегда.
  final List<String> legacyPrefixes;

  String get prefix => 'cache_${id}_';
}

/// Хранилище одного раздела кэша.
///
/// Сейчас это ключи `shared_preferences` с префиксом раздела. Если
/// понадобится вынести файлы на диск, менять нужно только этот класс.
class CacheStore {
  const CacheStore(this.section);

  final CacheSection section;

  String _key(String name) => '${section.prefix}$name';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> writeString(String name, String value) async {
    final prefs = await _prefs;
    await prefs.setString(_key(name), value);
  }

  Future<String?> readString(String name) async {
    final prefs = await _prefs;
    return prefs.getString(_key(name));
  }

  Future<void> writeJson(String name, Object value) =>
      writeString(name, jsonEncode(value));

  Future<Object?> readJson(String name) async {
    final raw = await readString(name);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (error) {
      throw AppException.cache(
        'Сохранённые данные повреждены. Очистите кэш в настройках.',
        cause: error,
      );
    }
  }

  Future<void> writeBytes(String name, List<int> bytes) =>
      writeString(name, base64Encode(bytes));

  Future<Uint8List?> readBytes(String name) async {
    final raw = await readString(name);
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (error) {
      throw AppException.cache(
        'Сохранённый файл повреждён. Очистите кэш в настройках.',
        cause: error,
      );
    }
  }

  Future<void> writeTimestamp(String name, DateTime at) =>
      writeString('$name::at', at.toIso8601String());

  Future<DateTime?> readTimestamp(String name) async {
    final raw = await readString('$name::at');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> remove(String name) async {
    final prefs = await _prefs;
    await prefs.remove(_key(name));
    await prefs.remove(_key('$name::at'));
  }

  /// Вес раздела в байтах.
  Future<int> sizeBytes() async {
    final prefs = await _prefs;
    var total = 0;
    for (final key in prefs.getKeys()) {
      if (!_matches(key)) continue;
      final value = prefs.get(key);
      if (value is String) {
        total += utf8.encode(value).length;
      } else if (value is List<String>) {
        total += utf8.encode(value.join()).length;
      }
    }
    return total;
  }

  /// Удаляет все ключи раздела, включая ключи старого формата.
  Future<void> clear() async {
    final prefs = await _prefs;
    final keys = prefs.getKeys().where(_matches).toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  bool _matches(String key) =>
      key.startsWith(section.prefix) ||
      section.legacyPrefixes.any(key.startsWith);
}

/// Сведения о разделе кэша для экрана настроек.
class CacheEntry {
  const CacheEntry({required this.section, required this.sizeBytes});

  final CacheSection section;
  final int sizeBytes;

  String get title => section.title;
  String get description => section.description;
  String get readableSize => formatBytes(sizeBytes);
  String get sizeLabel => isEmpty ? 'пусто' : readableSize;
  bool get isEmpty => sizeBytes == 0;
}

/// Обзор и очистка кэша.
class CacheManager {
  const CacheManager();

  Future<List<CacheEntry>> inspect() async {
    final entries = <CacheEntry>[];
    for (final section in CacheSection.values) {
      final size = await CacheStore(section).sizeBytes();
      entries.add(CacheEntry(section: section, sizeBytes: size));
    }
    return entries;
  }

  Future<int> totalSizeBytes() async {
    final entries = await inspect();
    return entries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
  }

  /// Очищает выбранные разделы и возвращает освобождённый объём.
  Future<int> clear(Iterable<CacheSection> sections) async {
    var freed = 0;
    for (final section in sections) {
      final store = CacheStore(section);
      freed += await store.sizeBytes();
      await store.clear();
    }
    return freed;
  }
}

/// «1.2 МБ», «340 КБ», «0 Б».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  final megabytes = bytes / (1024 * 1024);
  return '${megabytes.toStringAsFixed(1)} МБ';
}
