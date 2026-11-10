import 'dart:math' as math;

/// Тип узла карты.
enum MapNodeType {
  room, // аудитория
  stairs, // лестница
  entrance, // вход/выход
  corridor, // коридорная точка (не показывается)
  other, // столовая, туалет и т.п.
}

/// Точка в координатах плана этажа (пиксели SVG).
///
/// Своя точка вместо `Offset`, чтобы модели и алгоритм маршрута
/// не зависели от Flutter и могли тестироваться/запускаться отдельно.
class MapPoint {
  const MapPoint(this.x, this.y);

  final double x;
  final double y;

  static const MapPoint zero = MapPoint(0, 0);

  MapPoint operator +(MapPoint other) => MapPoint(x + other.x, y + other.y);
  MapPoint operator -(MapPoint other) => MapPoint(x - other.x, y - other.y);
  MapPoint operator *(double factor) => MapPoint(x * factor, y * factor);

  double distanceTo(MapPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is MapPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'MapPoint(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Один узел на плане этажа.
class MapNode {
  const MapNode({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    required this.type,
    this.stairsGroupId,
    this.connectsFloors = const <int>[],
  });

  final String id;
  final double x;
  final double y;
  final String label;
  final MapNodeType type;

  /// Группа лестницы: узлы с одинаковой группой на разных этажах
  /// — это одна и та же лестничная клетка.
  final String? stairsGroupId;

  /// Этажи, на которые ведёт эта лестница (для обычных узлов — пусто).
  final List<int> connectsFloors;

  MapPoint get position => MapPoint(x, y);

  bool get isStairs => type == MapNodeType.stairs;

  /// Через узел можно проходить транзитом (не только начинать/заканчивать путь).
  bool get isTransit =>
      type == MapNodeType.corridor || type == MapNodeType.stairs;

  bool get isVisible =>
      type != MapNodeType.corridor && (label.isNotEmpty || isStairs);

  /// Подпись для интерфейса: у лестниц без label — «лестница X».
  String get displayLabel {
    if (label.isNotEmpty) return label;
    if (isStairs && stairsGroupId != null) return 'лестница $stairsGroupId';
    return id;
  }

  @override
  String toString() => 'MapNode($id, $label, ${type.name})';
}

/// Ребро графа (связь между двумя узлами одного этажа).
class MapEdge {
  const MapEdge({required this.from, required this.to});

  final String from;
  final String to;
}

/// Готовая связь с предвычисленной стоимостью (пиксели плана).
class MapLink {
  const MapLink(this.node, this.cost);

  final MapNode node;
  final double cost;
}

/// Один этаж.
class MapFloor {
  MapFloor({
    required this.floor,
    required this.width,
    required this.height,
    required this.svgAsset,
    required List<MapNode> nodes,
    required List<MapEdge> edges,
    this.metersPerPixel,
  }) : nodes = List<MapNode>.unmodifiable(nodes),
       edges = List<MapEdge>.unmodifiable(edges),
       _byId = {for (final node in nodes) node.id: node},
       _links = _buildLinks(nodes, edges);

  final int floor;
  final double width;
  final double height;
  final String svgAsset;
  final List<MapNode> nodes;
  final List<MapEdge> edges;

  /// Масштаб плана: сколько метров в одном пикселе.
  /// null — масштаб неизвестен, используется значение по умолчанию.
  final double? metersPerPixel;

  final Map<String, MapNode> _byId;
  final Map<String, List<MapLink>> _links;

  MapNode? nodeById(String id) => _byId[id];

  bool hasNode(String id) => _byId.containsKey(id);

  /// Соседи узла с предвычисленной стоимостью перехода.
  List<MapLink> linksFrom(String nodeId) => _links[nodeId] ?? const <MapLink>[];

  /// Степень узла в графе этажа (0 — узел ни с чем не соединён).
  int degreeOf(String nodeId) => linksFrom(nodeId).length;

  static Map<String, List<MapLink>> _buildLinks(
    List<MapNode> nodes,
    List<MapEdge> edges,
  ) {
    final byId = {for (final node in nodes) node.id: node};
    final result = <String, List<MapLink>>{};
    for (final edge in edges) {
      final a = byId[edge.from];
      final b = byId[edge.to];
      if (a == null || b == null || a.id == b.id) continue;
      final cost = a.position.distanceTo(b.position);
      (result[a.id] ??= <MapLink>[]).add(MapLink(b, cost));
      (result[b.id] ??= <MapLink>[]).add(MapLink(a, cost));
    }
    return result;
  }
}
