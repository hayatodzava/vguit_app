import 'dart:convert';

import '../models/map_models.dart';
import 'nav_graph.dart';
import 'route_builder.dart';

/// Разобранные карты здания: этажи, граф и список замечаний к данным.
class MapData {
  MapData._({
    required this.floors,
    required this.floorsByNumber,
    required this.graph,
    required this.routeBuilder,
    required this.errors,
    required this.warnings,
  });

  final List<MapFloor> floors;
  final Map<int, MapFloor> floorsByNumber;
  final NavGraph graph;
  final RouteBuilder routeBuilder;

  /// Ошибки: этаж не загружен, ребро ведёт в несуществующий узел, дубликаты.
  final List<String> errors;

  /// Предупреждения: изолированные узлы, несимметричные лестницы и т.п.
  final List<String> warnings;

  bool get isEmpty => floors.isEmpty;

  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;

  List<int> get floorNumbers => floors.map((floor) => floor.floor).toList();

  /// Все точки, которые можно выбрать как «откуда/куда».
  late final List<({int floor, MapNode node})> visiblePoints = () {
    final points = <({int floor, MapNode node})>[];
    for (final floor in floors) {
      for (final node in floor.nodes) {
        if (!node.isVisible || node.type == MapNodeType.stairs) continue;
        points.add((floor: floor.floor, node: node));
      }
    }
    points.sort(
      (a, b) =>
          a.node.label.toLowerCase().compareTo(b.node.label.toLowerCase()),
    );
    return List<({int floor, MapNode node})>.unmodifiable(points);
  }();

  /// Все входы в здание.
  List<({int floor, MapNode node})> get entrances => visiblePoints
      .where((point) => point.node.type == MapNodeType.entrance)
      .toList(growable: false);

  ({int floor, MapNode node})? entranceOn(int floor) {
    for (final point in entrances) {
      if (point.floor == floor) return point;
    }
    return null;
  }

  /// Человекочитаемое имя этажа.
  static String floorLabel(int floor) => floor == -1 ? 'Цоколь' : '$floor этаж';

  /// Собирает [MapData] из разобранных этажей и проверяет данные.
  static MapData build({
    required List<MapFloor> floors,
    List<String>? errors,
    List<String>? warnings,
  }) {
    final errs = <String>[...?errors];
    final warns = <String>[...?warnings];
    final byNumber = <int, MapFloor>{};
    final ordered = <MapFloor>[];

    for (final floor in floors) {
      if (byNumber.containsKey(floor.floor)) {
        errs.add('Этаж ${floor.floor} описан дважды, второй файл пропущен');
        continue;
      }
      byNumber[floor.floor] = floor;
      ordered.add(floor);
    }
    ordered.sort((a, b) => a.floor.compareTo(b.floor));

    final graph = NavGraph(byNumber);

    for (final floor in ordered) {
      _validateFloor(floor, warns);
    }
    _validateStairs(ordered, byNumber, warns);
    _validateFloorConnectivity(graph, warns);

    return MapData._(
      floors: List<MapFloor>.unmodifiable(ordered),
      floorsByNumber: byNumber,
      graph: graph,
      routeBuilder: RouteBuilder(graph),
      errors: List<String>.unmodifiable(errs),
      warnings: List<String>.unmodifiable(warns),
    );
  }

  // ── Проверки данных ──

  static void _validateFloor(MapFloor floor, List<String> warnings) {
    final name = 'Этаж ${floor.floor}';

    final outOfBounds = floor.nodes
        .where(
          (node) =>
              node.x < 0 ||
              node.y < 0 ||
              node.x > floor.width ||
              node.y > floor.height,
        )
        .map((node) => node.id)
        .toList();
    if (outOfBounds.isNotEmpty) {
      warnings.add('$name: узлы за пределами плана ${_preview(outOfBounds)}');
    }

    final isolated = floor.nodes
        .where((node) => floor.degreeOf(node.id) == 0)
        .map((node) => node.displayLabel)
        .toList();
    if (isolated.isNotEmpty) {
      warnings.add('$name: не связаны с картой ${_preview(isolated)}');
    }

    // Комнаты, до которых нельзя дойти от коридора/лестницы/входа.
    final reachable = <String>{};
    final queue = <MapNode>[];
    for (final node in floor.nodes) {
      if (node.isTransit || node.type == MapNodeType.entrance) {
        if (reachable.add(node.id)) queue.add(node);
      }
    }
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final link in floor.linksFrom(current.id)) {
        if (reachable.add(link.node.id)) queue.add(link.node);
      }
    }
    final unreachable = floor.nodes
        .where(
          (node) =>
              !reachable.contains(node.id) && node.type != MapNodeType.corridor,
        )
        .map((node) => node.displayLabel)
        .toList();
    if (unreachable.isNotEmpty) {
      warnings.add('$name: недостижимые помещения ${_preview(unreachable)}');
    }
  }

  static void _validateStairs(
    List<MapFloor> floors,
    Map<int, MapFloor> byNumber,
    List<String> warnings,
  ) {
    final withoutGroup = <String>[];
    final claims = <String, Map<int, MapNode>>{}; // группа -> этаж -> узел

    for (final floor in floors) {
      for (final node in floor.nodes) {
        if (!node.isStairs) continue;
        final group = node.stairsGroupId;
        if (group == null || group.isEmpty) {
          withoutGroup.add('${floor.floor}/${node.id}');
          continue;
        }
        (claims[group] ??= <int, MapNode>{})[floor.floor] = node;
      }
    }
    if (withoutGroup.isNotEmpty) {
      warnings.add(
        'Лестницы без stairsGroupId (межэтажный маршрут через них невозможен): '
        '${_preview(withoutGroup)}',
      );
    }

    var reported = 0;
    claims.forEach((group, perFloor) {
      perFloor.forEach((floor, node) {
        for (final target in node.connectsFloors) {
          if (target == floor) continue;
          final other = perFloor[target];
          if (other == null) {
            if (byNumber.containsKey(target) && reported < 8) {
              warnings.add(
                'Лестница $group на этаже $floor ведёт на этаж $target, '
                'но там такой лестницы нет',
              );
              reported++;
            }
            continue;
          }
          if (!other.connectsFloors.contains(floor) && reported < 8) {
            warnings.add(
              'Лестница $group: этаж $floor указывает на $target, '
              'а этаж $target на $floor — нет',
            );
            reported++;
          }
        }
      });
    });
  }

  /// Проверяем связность этажей между собой (через лестницы).
  ///
  /// Разрывы коридоров ВНУТРИ этажа — не ошибка: крылья здания могут
  /// соединяться только через соседний этаж, и маршрут честно пойдёт обходом.
  static void _validateFloorConnectivity(
    NavGraph graph,
    List<String> warnings,
  ) {
    final components = graph.floorComponents();
    if (components.length > 1) {
      for (final component in components) {
        if (component.length < 2) {
          warnings.add(
            'Этаж ${component.first} не связан лестницами с другими этажами',
          );
        }
      }
    }
  }

  static String _preview(List<String> items, {int limit = 4}) {
    if (items.length <= limit) return items.join(', ');
    return '${items.take(limit).join(', ')} и ещё ${items.length - limit}';
  }
}

/// Разбор JSON-файла этажа.
///
/// Не бросает исключения на «мелких» проблемах: битые узлы и рёбра
/// пропускаются с записью в [errors]/[warnings], чтобы один испорченный
/// элемент не ломал весь этаж.
class MapDataParser {
  static MapFloor? parseFloor({
    required String source,
    required String jsonText,
    required String svgAsset,
    required List<String> errors,
    required List<String> warnings,
    int? expectedFloor,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      errors.add('$source: некорректный JSON (${e.message})');
      return null;
    }
    if (decoded is! Map) {
      errors.add('$source: ожидался объект JSON');
      return null;
    }
    final map = decoded.cast<String, Object?>();

    final floorValue = map['floor'];
    final floor = _asInt(floorValue);
    if (floor == null) {
      errors.add('$source: отсутствует или некорректен "floor" ($floorValue)');
      return null;
    }
    if (expectedFloor != null && floor != expectedFloor) {
      warnings.add(
        '$source: "floor" = $floor, а файл относится к этажу $expectedFloor',
      );
    }

    final width = _asDouble(map['imageWidth']);
    final height = _asDouble(map['imageHeight']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      errors.add('$source: некорректные imageWidth/imageHeight');
      return null;
    }

    final nodesRaw = map['nodes'];
    if (nodesRaw is! List || nodesRaw.isEmpty) {
      errors.add('$source: нет списка "nodes"');
      return null;
    }

    final nodes = <MapNode>[];
    final nodeIds = <String>{};
    for (final item in nodesRaw) {
      if (item is! Map) {
        warnings.add('$source: узел пропущен (не объект)');
        continue;
      }
      final node = item.cast<String, Object?>();
      final id = node['id'];
      if (id is! String || id.isEmpty) {
        warnings.add('$source: узел без "id" пропущен');
        continue;
      }
      if (!nodeIds.add(id)) {
        errors.add('$source: дублирующийся id узла «$id»');
        continue;
      }
      final x = _asDouble(node['x']);
      final y = _asDouble(node['y']);
      if (x == null || y == null) {
        warnings.add('$source: узел $id без координат пропущен');
        continue;
      }
      final connects = <int>[];
      final raw = node['connectsFloors'];
      if (raw is List) {
        for (final value in raw) {
          final parsed = _asInt(value);
          if (parsed != null) connects.add(parsed);
        }
      }
      nodes.add(
        MapNode(
          id: id,
          x: x,
          y: y,
          label: node['label']?.toString().trim() ?? '',
          type: _nodeType(node['type']),
          stairsGroupId: node['stairsGroupId']?.toString().trim(),
          connectsFloors: List<int>.unmodifiable(connects),
        ),
      );
    }
    if (nodes.isEmpty) {
      errors.add('$source: не разобрано ни одного узла');
      return null;
    }

    final edges = <MapEdge>[];
    final seenEdges = <String>{};
    final edgesRaw = map['edges'];
    if (edgesRaw is List) {
      for (final item in edgesRaw) {
        if (item is! Map) continue;
        final edge = item.cast<String, Object?>();
        final from = edge['from'];
        final to = edge['to'];
        if (from is! String || to is! String) continue;
        if (!nodeIds.contains(from) || !nodeIds.contains(to)) {
          errors.add(
            '$source: ребро $from–$to ссылается на несуществующий узел',
          );
          continue;
        }
        if (from == to) {
          warnings.add('$source: петля на узле $from');
          continue;
        }
        final key = from.compareTo(to) < 0 ? '$from|$to' : '$to|$from';
        if (!seenEdges.add(key)) {
          warnings.add('$source: повторяющееся ребро $from–$to');
          continue;
        }
        edges.add(MapEdge(from: from, to: to));
      }
    }

    return MapFloor(
      floor: floor,
      width: width,
      height: height,
      svgAsset: svgAsset,
      nodes: nodes,
      edges: edges,
      metersPerPixel: _asDouble(map['metersPerPixel']),
    );
  }

  static MapNodeType _nodeType(Object? raw) {
    switch (raw) {
      case 'room':
        return MapNodeType.room;
      case 'stairs':
        return MapNodeType.stairs;
      case 'entrance':
        return MapNodeType.entrance;
      case 'corridor':
        return MapNodeType.corridor;
      default:
        return MapNodeType.other;
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
