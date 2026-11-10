import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/map_models.dart';
import 'map_data.dart';

/// Загрузка карт этажей из ассетов.
class MapLoader {
  const MapLoader._();

  /// Список этажей с привязкой к файлам.
  static const List<({int floor, String json, String svg})> floorFiles = [
    (
      floor: -1,
      json: 'assets/map/floor_-1.json',
      svg: 'assets/map/floor_-1.svg',
    ),
    (floor: 1, json: 'assets/map/floor_1.json', svg: 'assets/map/floor_1.svg'),
    (floor: 2, json: 'assets/map/floor_2.json', svg: 'assets/map/floor_2.svg'),
    (floor: 3, json: 'assets/map/floor_3.json', svg: 'assets/map/floor_3.svg'),
    (floor: 4, json: 'assets/map/floor_4.json', svg: 'assets/map/floor_4.svg'),
    (floor: 5, json: 'assets/map/floor_5.json', svg: 'assets/map/floor_5.svg'),
  ];

  /// Загружает и разбирает все этажи.
  ///
  /// Битый файл не ломает остальные: причина попадает в [MapData.errors].
  static Future<MapData> loadAll() async {
    final errors = <String>[];
    final warnings = <String>[];
    final floors = <MapFloor>[];

    for (final file in floorFiles) {
      try {
        final raw = await rootBundle.loadString(file.json);
        final floor = MapDataParser.parseFloor(
          source: file.json,
          jsonText: raw,
          svgAsset: file.svg,
          errors: errors,
          warnings: warnings,
          expectedFloor: file.floor,
        );
        if (floor != null) floors.add(floor);
      } catch (error) {
        errors.add('${file.json}: не удалось прочитать ($error)');
      }
    }

    final data = MapData.build(
      floors: floors,
      errors: errors,
      warnings: warnings,
    );

    if (kDebugMode) {
      for (final issue in data.errors) {
        debugPrint('[map] ошибка: $issue');
      }
      for (final issue in data.warnings) {
        debugPrint('[map] предупреждение: $issue');
      }
    }
    return data;
  }
}
