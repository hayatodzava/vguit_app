import '../models/map_models.dart';

/// Позиция в здании: этаж + идентификатор узла.
///
/// `MapNode.id` уникален только внутри этажа (например, `n_1` есть и на
/// минус первом, и на пятом этаже), поэтому снаружи узлы адресуются парой.
class NavSpot {
  const NavSpot(this.floor, this.nodeId);

  final int floor;
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is NavSpot && other.floor == floor && other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(floor, nodeId);

  @override
  String toString() => 'NavSpot($floor, $nodeId)';
}

/// Переход из текущей позиции в соседнюю.
class NavLink {
  const NavLink({
    required this.to,
    required this.cost,
    this.stairs = false,
    this.stairsGroupId,
  });

  final NavSpot to;

  /// Стоимость перехода в метрах — единая единица для всего графа.
  final double cost;

  /// Переход по лестнице (между этажами).
  final bool stairs;

  /// Группа лестницы, если [stairs].
  final String? stairsGroupId;

  @override
  String toString() =>
      'NavLink(-> $to, ${cost.toStringAsFixed(1)} м${stairs ? ", stairs $stairsGroupId" : ""})';
}

/// Граф всего здания: связи внутри этажей + межэтажные связи по лестницам.
///
/// Создаётся один раз после загрузки карт; все рёбра и стоимости
/// предвычислены в метрах, поэтому обход в A* не выполняет поиск по спискам
/// и не зависит от масштаба конкретного этажа.
class NavGraph {
  NavGraph(
    Map<int, MapFloor> floors, {
    this.metersPerPixel = defaultMetersPerPixel,
    this.stairsMetersPerFloor = defaultStairsMetersPerFloor,
  }) : floors = Map<int, MapFloor>.unmodifiable(Map<int, MapFloor>.of(floors)) {
    _localLinks = _buildLocalLinks(this.floors, metersPerPixel);
    _stairsLinks = _buildStairsLinks(this.floors, stairsMetersPerFloor);
  }

  /// Масштаб этажа, если в JSON не указан `metersPerPixel`.
  ///
  /// 305 пикселей плана ≈ 55 метров, то есть ≈ 0.18 м на пиксель.
  static const double defaultMetersPerPixel = 0.1803;

  /// Сколько метров «по полу» эквивалентен подъём на один этаж.
  static const double defaultStairsMetersPerFloor = 18.0;

  final Map<int, MapFloor> floors;

  /// Масштаб по умолчанию (м/пиксель) для этажей без своего значения.
  final double metersPerPixel;

  /// Стоимость подъёма на один этаж в метрах.
  final double stairsMetersPerFloor;

  late final Map<NavSpot, List<NavLink>> _localLinks;
  late final Map<NavSpot, List<NavLink>> _stairsLinks;

  Iterable<int> get floorNumbers => floors.keys;

  MapNode? nodeAt(NavSpot spot) => floors[spot.floor]?.nodeById(spot.nodeId);

  bool contains(NavSpot spot) => nodeAt(spot) != null;

  /// Сколько метров в пикселе на конкретном этаже.
  double scaleFor(int floor) => floors[floor]?.metersPerPixel ?? metersPerPixel;

  /// Соседи позиции: сначала того же этажа, затем межэтажные переходы.
  Iterable<NavLink> linksFrom(NavSpot spot) sync* {
    final local = _localLinks[spot];
    if (local != null) yield* local;
    final stairs = _stairsLinks[spot];
    if (stairs != null) yield* stairs;
  }

  /// Связаны ли два этажа хотя бы одной лестницей.
  bool floorsConnected(int from, int to) {
    if (from == to) return true;
    for (final entry in _stairsLinks.entries) {
      if (entry.key.floor != from) continue;
      for (final link in entry.value) {
        if (link.to.floor == to) return true;
      }
    }
    return false;
  }

  /// Компоненты связности этажей (через лестницы).
  List<Set<int>> floorComponents() {
    final remaining = floors.keys.toSet();
    final components = <Set<int>>[];
    while (remaining.isNotEmpty) {
      final start = remaining.first;
      final component = <int>{start};
      final queue = <int>[start];
      remaining.remove(start);
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        for (final floor in remaining.toList()) {
          if (floorsConnected(current, floor)) {
            component.add(floor);
            remaining.remove(floor);
            queue.add(floor);
          }
        }
      }
      components.add(component);
    }
    return components;
  }

  static Map<NavSpot, List<NavLink>> _buildLocalLinks(
    Map<int, MapFloor> floors,
    double fallbackScale,
  ) {
    final result = <NavSpot, List<NavLink>>{};
    for (final floor in floors.values) {
      final scale = floor.metersPerPixel ?? fallbackScale;
      for (final node in floor.nodes) {
        final links = floor.linksFrom(node.id);
        if (links.isEmpty) continue;
        result[NavSpot(floor.floor, node.id)] = <NavLink>[
          for (final link in links)
            NavLink(
              to: NavSpot(floor.floor, link.node.id),
              cost: link.cost * scale,
            ),
        ];
      }
    }
    return result;
  }

  static Map<NavSpot, List<NavLink>> _buildStairsLinks(
    Map<int, MapFloor> floors,
    double metersPerFloor,
  ) {
    // группа -> этаж -> лестничные узлы
    final byGroup = <String, Map<int, List<MapNode>>>{};
    for (final floor in floors.values) {
      for (final node in floor.nodes) {
        final group = node.stairsGroupId;
        if (!node.isStairs || group == null || group.isEmpty) continue;
        final perFloor = byGroup.putIfAbsent(
          group,
          () => <int, List<MapNode>>{},
        );
        (perFloor[floor.floor] ??= <MapNode>[]).add(node);
      }
    }

    final result = <NavSpot, List<NavLink>>{};
    byGroup.forEach((group, perFloor) {
      final floorsOfGroup = perFloor.keys.toList()..sort();
      for (var i = 0; i < floorsOfGroup.length; i++) {
        for (var j = i + 1; j < floorsOfGroup.length; j++) {
          final floorA = floorsOfGroup[i];
          final floorB = floorsOfGroup[j];
          // Обе стороны должны подтверждать переход — иначе это опечатка
          // в данных, и половина маршрута окажется «висячей».
          for (final a in perFloor[floorA]!) {
            for (final b in perFloor[floorB]!) {
              if (!a.connectsFloors.contains(floorB)) continue;
              if (!b.connectsFloors.contains(floorA)) continue;
              final cost = metersPerFloor * (floorB - floorA).abs();
              (result[NavSpot(floorA, a.id)] ??= <NavLink>[]).add(
                NavLink(
                  to: NavSpot(floorB, b.id),
                  cost: cost,
                  stairs: true,
                  stairsGroupId: group,
                ),
              );
              (result[NavSpot(floorB, b.id)] ??= <NavLink>[]).add(
                NavLink(
                  to: NavSpot(floorA, a.id),
                  cost: cost,
                  stairs: true,
                  stairsGroupId: group,
                ),
              );
            }
          }
        }
      }
    });
    return result;
  }
}
