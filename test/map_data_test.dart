import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/map_models.dart';
import 'package:vguit_app/services/map_data.dart';

/// Проверки реальных данных из assets/map.
///
/// Ловят типичные ошибки ручного редактирования карт: забытый номер этажа,
/// ребро в несуществующий узел, лестницу без группы, оторванную комнату.
void main() {
  const floorFiles = <int, String>{
    -1: 'assets/map/floor_-1.json',
    1: 'assets/map/floor_1.json',
    2: 'assets/map/floor_2.json',
    3: 'assets/map/floor_3.json',
    4: 'assets/map/floor_4.json',
    5: 'assets/map/floor_5.json',
  };

  late MapData data;

  setUpAll(() {
    final floors = <MapFloor>[];
    final errors = <String>[];
    final warnings = <String>[];
    floorFiles.forEach((floorNumber, path) {
      floors.add(
        MapDataParser.parseFloor(
          source: path,
          jsonText: File(path).readAsStringSync(),
          svgAsset: path.replaceAll('.json', '.svg'),
          errors: errors,
          warnings: warnings,
          expectedFloor: floorNumber,
        )!,
      );
    });
    data = MapData.build(floors: floors, errors: errors, warnings: warnings);
  });

  test('все этажи загружены и без ошибок разбора', () {
    expect(data.floors.map((f) => f.floor), [-1, 1, 2, 3, 4, 5]);
    expect(data.errors, isEmpty);
  });

  test('в каждом этаже есть лестницы с привязкой к этажам', () {
    for (final floor in data.floors) {
      final stairs = floor.nodes.where((n) => n.isStairs).toList();
      expect(stairs, isNotEmpty, reason: 'этаж ${floor.floor} без лестниц');
      for (final node in stairs) {
        expect(
          node.stairsGroupId,
          isNotNull,
          reason: 'лестница ${node.id} на этаже ${floor.floor} без группы',
        );
        expect(
          node.connectsFloors,
          isNotEmpty,
          reason:
              'лестница ${node.id} на этаже ${floor.floor} без connectsFloors',
        );
      }
    }
  });

  test('этажи связаны между собой лестницами', () {
    final components = data.graph.floorComponents();
    expect(
      components,
      hasLength(1),
      reason: 'этажи распались на компоненты: $components',
    );
  });

  test('из каждой аудитории достижим вход на 1 этаже', () {
    final entrance = data.entranceOn(1);
    expect(entrance, isNotNull, reason: 'на 1 этаже нет входа');
    final start = entrance!;

    final unreachable = <String>[];
    for (final point in data.visiblePoints) {
      if (point.node.type != MapNodeType.room) continue;
      final route = data.routeBuilder.findRoute(
        startFloor: start.floor,
        startNodeId: start.node.id,
        endFloor: point.floor,
        endNodeId: point.node.id,
      );
      if (route == null) {
        unreachable.add(
          '${point.node.displayLabel} '
          '(${MapData.floorLabel(point.floor)})',
        );
      }
    }
    expect(
      unreachable,
      isEmpty,
      reason: 'нет маршрута до аудиторий: ${unreachable.join(', ')}',
    );
  });

  test('в этаже не бывает ребра в несуществующий узел', () {
    for (final floor in data.floors) {
      for (final edge in floor.edges) {
        expect(
          floor.hasNode(edge.from),
          isTrue,
          reason: 'этаж ${floor.floor}: нет узла ${edge.from}',
        );
        expect(
          floor.hasNode(edge.to),
          isTrue,
          reason: 'этаж ${floor.floor}: нет узла ${edge.to}',
        );
      }
    }
  });

  test('известные маршруты имеют разумную длину', () {
    final entrance = data.entranceOn(1)!;
    final target = data.visiblePoints.firstWhere(
      (point) => point.floor == 5 && point.node.type == MapNodeType.room,
      orElse: () => throw StateError('на 5 этаже нет аудиторий'),
    );
    final route = data.routeBuilder.findRoute(
      startFloor: entrance.floor,
      startNodeId: entrance.node.id,
      endFloor: target.floor,
      endNodeId: target.node.id,
    )!;

    expect(
      route.transitions,
      isNotEmpty,
      reason: 'путь на другой этаж без перехода по лестнице',
    );
    expect(route.distanceMeters, greaterThan(20));
    expect(route.distanceMeters, lessThan(600));
    expect(route.stairsMeters, greaterThan(0));
    expect(route.eta.inSeconds, greaterThan(0));
  });
}
