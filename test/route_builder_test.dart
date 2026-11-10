import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/map_models.dart';
import 'package:vguit_app/services/map_data.dart';
import 'package:vguit_app/services/nav_graph.dart';
import 'package:vguit_app/services/route_builder.dart';

MapNode room(String id, double x, double y, [String? label]) =>
    MapNode(id: id, x: x, y: y, label: label ?? id, type: MapNodeType.room);

MapNode corridor(String id, double x, double y) =>
    MapNode(id: id, x: x, y: y, label: '', type: MapNodeType.corridor);

MapNode stairs(String id, double x, double y, String group, List<int> floors) =>
    MapNode(
      id: id,
      x: x,
      y: y,
      label: 'лестница $group',
      type: MapNodeType.stairs,
      stairsGroupId: group,
      connectsFloors: floors,
    );

MapFloor floor(
  int number,
  List<MapNode> nodes,
  List<MapEdge> edges, {
  double metersPerPixel = 0.1,
}) => MapFloor(
  floor: number,
  width: 2000,
  height: 1200,
  svgAsset: 'test.svg',
  nodes: nodes,
  edges: edges,
  metersPerPixel: metersPerPixel,
);

List<MapEdge> chain(List<String> ids) {
  final edges = <MapEdge>[];
  for (var i = 0; i < ids.length - 1; i++) {
    edges.add(MapEdge(from: ids[i], to: ids[i + 1]));
  }
  return edges;
}

RouteBuilder builderFor(List<MapFloor> floors) =>
    MapData.build(floors: floors).routeBuilder;

void main() {
  group('стоимость пути', () {
    test('прямой путь дешевле зигзага из коротких шагов', () {
      // Прямое ребро 158 px. Зигзаг из четырёх коротких шагов — 200 px,
      // но сумма КВАДРАТОВ длин у него меньше, поэтому на старом весе
      // (квадрат расстояния) алгоритм выбирал именно его.
      final zigzag = [
        room('a', 0, 0),
        room('b', 158, 0),
        corridor('c', 40, 20),
        corridor('d', 80, -20),
        corridor('e', 120, 20),
      ];

      final floors = [
        floor(1, zigzag, [
          const MapEdge(from: 'a', to: 'b'),
          ...chain(['a', 'c', 'd', 'e', 'b']),
        ]),
      ];

      final result = builderFor(
        floors,
      ).findRoute(startFloor: 1, startNodeId: 'a', endFloor: 1, endNodeId: 'b');

      expect(result, isNotNull);
      expect(result!.steps.map((s) => s.node.id), ['a', 'b']);
      // 158 px при 0.1 м/px.
      expect(result.cost, closeTo(15.8, 0.001));
    });

    test('стоимость равна сумме длин шагов', () {
      final floors = [
        floor(1, [
          room('a', 0, 0),
          corridor('c1', 100, 0),
          corridor('c2', 100, 100),
          room('b', 100, 200),
        ], chain(['a', 'c1', 'c2', 'b'])),
      ];

      final result = builderFor(floors).findRoute(
        startFloor: 1,
        startNodeId: 'a',
        endFloor: 1,
        endNodeId: 'b',
      )!;

      final expected =
          (math.sqrt(100 * 100 + 0) +
              math.sqrt(0 + 100 * 100) +
              math.sqrt(0 + 100 * 100)) *
          0.1;
      expect(result.cost, closeTo(expected, 0.001));
      expect(result.distanceMeters, closeTo(expected, 0.001));
      expect(result.steps.length, 4);
      expect(result.transitionCount, 0);
    });
  });

  group('этажи и лестницы', () {
    List<MapFloor> twoFloors({required bool linkStairs}) {
      final stairsFloors = linkStairs ? <int>[1, 2] : <int>[1];
      return [
        floor(1, [
          room('a', 0, 0),
          corridor('c1', 100, 0),
          stairs('s1', 200, 0, 'A', stairsFloors),
        ], chain(['a', 'c1', 's1'])),
        floor(2, [
          stairs('s1', 200, 0, 'A', linkStairs ? <int>[1, 2] : <int>[1]),
          corridor('c2', 100, 0),
          room('b', 0, 0),
        ], chain(['s1', 'c2', 'b'])),
      ];
    }

    test('маршрут между этажами идёт по лестнице', () {
      final result = builderFor(
        twoFloors(linkStairs: true),
      ).findRoute(startFloor: 1, startNodeId: 'a', endFloor: 2, endNodeId: 'b');

      expect(result, isNotNull);
      expect(result!.transitions, hasLength(1));
      expect(result.transitions.single.fromFloor, 1);
      expect(result.transitions.single.toFloor, 2);
      expect(result.floors, [1, 2]);
      expect(
        result.stairsMeters,
        closeTo(NavGraph.defaultStairsMetersPerFloor, 0.001),
      );
      expect(result.distanceMeters, closeTo(result.cost, 0.001));
      expect(
        result.steps.where((step) => step.isTransition).map((s) => s.floor),
        [2],
        reason: 'шаг на новом этаже помечается как переход',
      );
    });

    test('без общей лестницы между этажами маршрута нет', () {
      final result = builderFor(
        twoFloors(linkStairs: false),
      ).findRoute(startFloor: 1, startNodeId: 'a', endFloor: 2, endNodeId: 'b');
      expect(result, isNull);
    });

    test('лестница дороже, но путь всё равно находится', () {
      final result = builderFor(twoFloors(linkStairs: true)).findRoute(
        startFloor: 2,
        startNodeId: 'b',
        endFloor: 1,
        endNodeId: 'a',
      )!;
      // 200 px * 0.1 = 20 м по второму этажу, 18 м за этаж
      // и ещё 200 px * 0.1 = 20 м по первому.
      expect(result.cost, closeTo(20 + 18 + 20, 0.001));
    });
  });

  group('ограничения графа', () {
    test('через аудиторию нельзя проходить транзитом', () {
      // c1 -- комнатка -- c2: единственный «проход» лежит через аудиторию.
      final floors = [
        floor(
          1,
          [
            corridor('c1', 0, 0),
            room('pass', 100, 0),
            corridor('c2', 200, 0),
            room('a', 0, 100),
            room('b', 200, 100),
          ],
          [
            ...chain(['a', 'c1', 'pass', 'c2', 'b']),
          ],
        ),
      ];

      final result = builderFor(
        floors,
      ).findRoute(startFloor: 1, startNodeId: 'a', endFloor: 1, endNodeId: 'b');
      expect(result, isNull);
    });

    test('начало и конец совпадают', () {
      final floors = [
        floor(1, [room('a', 0, 0)], const <MapEdge>[]),
      ];
      final result = builderFor(floors).findRoute(
        startFloor: 1,
        startNodeId: 'a',
        endFloor: 1,
        endNodeId: 'a',
      )!;
      expect(result.isEmpty, isTrue);
      expect(result.cost, 0);
    });

    test('несуществующий узел даёт null', () {
      final floors = [
        floor(1, [room('a', 0, 0)], const <MapEdge>[]),
      ];
      final builder = builderFor(floors);
      expect(
        builder.findRoute(
          startFloor: 1,
          startNodeId: 'a',
          endFloor: 9,
          endNodeId: 'a',
        ),
        isNull,
      );
    });
  });

  group('метры и время', () {
    test('расстояние переводится через метры на пиксель', () {
      final floors = [
        floor(1, [
          room('a', 0, 0),
          corridor('c', 100, 0),
          room('b', 200, 0),
        ], chain(['a', 'c', 'b'])),
      ];
      final data = MapData.build(floors: floors);
      final builder = RouteBuilder(
        NavGraph(data.floorsByNumber, metersPerPixel: 0.1),
        walkingSpeed: 1.0,
      );
      final result = builder.findRoute(
        startFloor: 1,
        startNodeId: 'a',
        endFloor: 1,
        endNodeId: 'b',
      )!;
      // 200 px * 0.1 м/px = 20 м, при 1 м/с — 20 секунд.
      expect(result.distanceMeters, closeTo(20, 0.001));
      expect(result.eta.inSeconds, 20);
      expect(result.stairsMeters, 0);
    });

    test('масштаб берётся из этажа, а не общий', () {
      final floors = [
        floor(
          1,
          [room('a', 0, 0), corridor('c', 100, 0), room('b', 200, 0)],
          chain(['a', 'c', 'b']),
          metersPerPixel: 0.2,
        ),
      ];
      final data = MapData.build(floors: floors);
      final result = data.routeBuilder.findRoute(
        startFloor: 1,
        startNodeId: 'a',
        endFloor: 1,
        endNodeId: 'b',
      )!;
      expect(result.distanceMeters, closeTo(40, 0.001));
    });
  });
}
