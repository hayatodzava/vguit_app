import 'dart:typed_data';

import 'cache/cache_store.dart';

/// Кэш скачанных Excel-файлов расписания студентов.
///
/// Файл хранится целиком вместе с меткой времени обновления; раздел кэша
/// «Расписание студентов» можно взвесить и очистить из настроек.
class ScheduleCache {
  const ScheduleCache();

  static const CacheStore _store = CacheStore(CacheSection.studentsSchedule);

  Future<void> saveBytes(String facultyKey, Uint8List bytes) async {
    await _store.writeBytes('xlsx_$facultyKey', bytes);
    await _store.writeTimestamp('xlsx_$facultyKey', DateTime.now());
  }

  Future<Uint8List?> loadBytes(String facultyKey) =>
      _store.readBytes('xlsx_$facultyKey');

  Future<DateTime?> loadUpdatedAt(String facultyKey) =>
      _store.readTimestamp('xlsx_$facultyKey');

  Future<void> remove(String facultyKey) => _store.remove('xlsx_$facultyKey');

  Future<void> clearAll() => _store.clear();
}
