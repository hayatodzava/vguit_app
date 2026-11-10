import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;

import 'net.dart';
import 'schedule_parser.dart';

/// Откуда берётся расписание студентов: адреса файлов и скачивание.
///
/// Один источник для экрана расписания и для фоновой проверки —
/// чтобы адреса не расходились.
class ScheduleSources {
  const ScheduleSources._();

  static const Map<String, String> facultyUrls = <String, String>{
    'УИТС': 'https://vsuet.ru/images/student/schedule/uits.xlsx',
    'ИТХ': 'https://vsuet.ru/images/student/schedule/itf.xlsx',
    'ЭХТ': 'https://vsuet.ru/images/student/schedule/eht.xlsx',
    'ТХ': 'https://vsuet.ru/images/student/schedule/tf.xlsx',
    'ЭИУ': 'https://vsuet.ru/images/student/schedule/eiu.xlsx',
  };

  static List<String> get faculties => facultyUrls.keys.toList(growable: false);

  /// Скачивает Excel-файл расписания факультета.
  ///
  /// Пробует основной адрес и вариант с «1» в имени файла.
  static Future<Uint8List> download(String faculty, {String? action}) async {
    final baseUrl = facultyUrls[faculty];
    if (baseUrl == null) {
      throw AppException('Неизвестный факультет «$faculty».');
    }

    final candidates = <String>{
      baseUrl,
      baseUrl.replaceAll('.xlsx', '1.xlsx'),
    }.toList(growable: false);

    Object? lastError;
    for (final url in candidates) {
      try {
        final response = await httpDownload(
          Uri.parse(url),
          action: action ?? 'Скачивание расписания',
        );
        final body = response.bodyBytes;
        if (body.length > 4 && body[0] == 0x50 && body[1] == 0x4B) {
          return body;
        }
        lastError = AppException.parse(
          'Файл по адресу $url скачался, но это не Excel-книга.',
        );
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is AppException) throw lastError;
    throw AppException.from(
      lastError ?? Exception('нет ответа'),
      action: 'Скачивание расписания',
    );
  }

  /// Соответствие «группа → лист (курс)» по всему файлу факультета.
  ///
  /// Нужно, чтобы можно было выбрать любую группу факультета и сразу
  /// переключиться на курс, где она находится.
  static Map<String, String> groupCourses(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final result = <String, String>{};
    for (final sheetName in excel.tables.keys) {
      try {
        final data = ScheduleParser.parse(
          excel: excel,
          sheetName: sheetName,
          faculty: '',
        );
        for (final group in data.groupCols) {
          final name = group.name.trim();
          if (name.isEmpty) continue;
          // Если группа встречается на нескольких листах — оставляем первый.
          result.putIfAbsent(name, () => sheetName);
        }
      } catch (_) {
        // Лист другого формата (титульный и т.п.) — пропускаем.
      }
    }
    return result;
  }

  /// Список всех групп факультета по уже скачанному файлу.
  static List<String> groupNames(Uint8List bytes) {
    final names = groupCourses(bytes).keys.toList()..sort();
    return List<String>.unmodifiable(names);
  }
}
