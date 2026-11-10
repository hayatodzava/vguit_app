// Проверка данных карты и алгоритма маршрута без запуска приложения.
//
//   dart run tool/map_check.dart
//
// Читает assets/map/*.json, печатает замечания к данным, проверяет, что A*
// находит путь той же стоимости, что и полный перебор (Дейкстра), и гоняет
// несколько маршрутов по реальному зданию.
//
// Смысл: правки карт (координаты, рёбра, лестницы) можно проверять
// за секунду, не собирая приложение.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:vguit_app/models/map_models.dart';
import 'package:vguit_app/services/map_data.dart';
import 'package:vguit_app/services/nav_graph.dart';

void main(List<String> args) {
  final floors = <MapFloor>[];
  final errors = <String>[];
  final warnings = <String>[];

  const files = <({int floor, String json, String svg})>[
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

  for (final file in files) {
    final path = file.json;
    final source = File(path);
    if (!source.existsSync()) {
      errors.add('$path: файл не найден');
      continue;
    }
    final parsed = MapDataParser.parseFloor(
      source: path,
      jsonText: source.readAsStringSync(),
      svgAsset: file.svg,
      errors: errors,
      warnings: warnings,
      expectedFloor: file.floor,
    );
    if (parsed != null) floors.add(parsed);
  }

  final data = MapData.build(
    floors: floors,
    errors: errors,
    warnings: warnings,
  );

  print('═══ Данные ═══');
  for (final floor in data.floors) {
    final rooms = floor.nodes.where((n) => n.type == MapNodeType.room).length;
    final stairs = floor.nodes.where((n) => n.isStairs).length;
    final entrances = floor.nodes
        .where((n) => n.type == MapNodeType.entrance)
        .length;
    print(
      '  ${MapData.floorLabel(floor.floor)}: '
      'узлов ${floor.nodes.length}, рёбер ${floor.edges.length}, '
      'аудиторий $rooms, лестниц $stairs, входов $entrances',
    );
  }

  print('\n═══ Ошибки (${data.errors.length}) ═══');
  for (final issue in data.errors) {
    print('  ! $issue');
  }
  print('\n═══ Предупреждения (${data.warnings.length}) ═══');
  for (final issue in data.warnings) {
    print('  ? $issue');
  }

  print('\n═══ Связность этажей ═══');
  final components = data.graph.floorComponents();
  for (final component in components) {
    print('  ${component.map(MapData.floorLabel).join(' ↔ ')}');
  }

  // ── A* против Дейкстры на всех парах «вход → аудитория» ──
  final entrances = data.entrances;
  if (entrances.isEmpty) {
    print('\nВходов не найдено — проверять маршруты не от чего');
    return;
  }
  final start = entrances.first;
  final rooms = data.visiblePoints
      .where((p) => p.node.type == MapNodeType.room)
      .toList(growable: false);

  print(
    '\n═══ Маршруты: ${start.node.displayLabel} '
    '(${MapData.floorLabel(start.floor)}) ═══',
  );

  var checked = 0;
  var mismatched = 0;
  var unreachable = 0;
  final byFloor = <int, List<String>>{};

  for (final room in rooms) {
    final result = data.routeBuilder.findRoute(
      startFloor: start.floor,
      startNodeId: start.node.id,
      endFloor: room.floor,
      endNodeId: room.node.id,
    );
    checked++;

    final reference = _dijkstra(
      data.graph,
      NavSpot(start.floor, start.node.id),
      NavSpot(room.floor, room.node.id),
    );

    if (result == null) {
      if (reference != null) {
        mismatched++;
        print(
          '  ✗ ${room.node.displayLabel}: A* не нашёл путь, '
          'а Дейкстра нашла (${reference.toStringAsFixed(1)})',
        );
      } else {
        unreachable++;
        print(
          '  ✗ ${room.node.displayLabel} '
          '(${MapData.floorLabel(room.floor)}): пути нет ни у A*, '
          'ни у Дейкстры',
        );
      }
      continue;
    }
    if (reference == null || (result.cost - reference).abs() > 0.001) {
      mismatched++;
      print(
        '  ✗ ${room.node.displayLabel}: стоимость A* '
        '${result.cost.toStringAsFixed(1)} ≠ Дейкстры '
        '${reference?.toStringAsFixed(1)}',
      );
    }

    final floorKey = room.floor;
    final entry = byFloor.putIfAbsent(floorKey, () => <String>[]);
    if (entry.length < 2) {
      final floorPath = result.floors.map(MapData.floorLabel).join(' → ');
      entry.add(
        '${room.node.displayLabel}: '
        '${result.distanceMeters.round()} м, '
        '${result.eta.inMinutes} мин, '
        'шагов ${result.steps.length}, '
        'этажи: $floorPath',
      );
    }
  }

  byFloor.forEach((floor, lines) {
    for (final line in lines) {
      print('  → ${MapData.floorLabel(floor)}: $line');
    }
  });

  print(
    '\n  проверено пар: $checked, '
    'недостижимых: $unreachable, '
    'расхождений с эталоном: $mismatched',
  );

  // ── Проверка «зигзага»: путь должен быть кратчайшим, а не из коротких шагов ──
  print('\n═══ Пример маршрута ═══');
  final far = rooms.isEmpty ? null : rooms.last;
  if (far != null) {
    final result = data.routeBuilder.findRoute(
      startFloor: start.floor,
      startNodeId: start.node.id,
      endFloor: far.floor,
      endNodeId: far.node.id,
    );
    if (result == null) {
      print('  путь не найден');
    } else {
      for (final step in result.steps) {
        print(
          '  ${step.floor}: ${step.node.displayLabel}'
          '${step.isTransition ? "  (после лестницы)" : ""}'
          '  ${step.segmentCost.toStringAsFixed(1)} м',
        );
      }
      print(
        '  стоимость ${result.cost.toStringAsFixed(1)} м, '
        '${result.distanceMeters.round()} м, ${result.eta.inMinutes} мин',
      );
      for (final transition in result.transitions) {
        print(
          '  переход: ${transition.label} '
          '${transition.fromFloor} → ${transition.toFloor}',
        );
      }
    }
  }
}

/// Полный перебор (Дейкстра) как эталон стоимости.
double? _dijkstra(NavGraph graph, NavSpot start, NavSpot end) {
  final best = <NavSpot, double>{start: 0};
  final visited = <NavSpot>{};
  while (true) {
    NavSpot? current;
    var currentCost = double.infinity;
    best.forEach((spot, cost) {
      if (!visited.contains(spot) && cost < currentCost) {
        currentCost = cost;
        current = spot;
      }
    });
    if (current == null) return null;
    if (current == end) return currentCost;
    visited.add(current!);
    for (final link in graph.linksFrom(current!)) {
      final target = graph.nodeAt(link.to);
      if (target == null) continue;
      final isTarget = link.to == end;
      if (!isTarget && !target.isTransit) continue;
      final candidate = currentCost + link.cost;
      if (candidate < (best[link.to] ?? double.infinity)) {
        best[link.to] = candidate;
      }
    }
  }
}
