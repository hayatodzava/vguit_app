import '../models/map_models.dart';
import 'nav_graph.dart';

/// Один шаг маршрута — узел на конкретном этаже.
class RouteStep {
  const RouteStep({
    required this.floor,
    required this.node,
    this.isTransition = false,
    this.segmentCost = 0,
  });

  final int floor;
  final MapNode node;

  /// Шаг начинается с межэтажного перехода (пришли по лестнице).
  final bool isTransition;

  /// Длина перехода от предыдущего шага в метрах.
  final double segmentCost;
}

/// Межэтажный переход: по какой лестнице и с какого этажа на какой.
class RouteTransition {
  const RouteTransition({
    required this.fromFloor,
    required this.toFloor,
    required this.fromStairs,
    required this.toStairs,
    this.stairsGroupId,
  });

  final int fromFloor;
  final int toFloor;
  final MapNode fromStairs;
  final MapNode toStairs;
  final String? stairsGroupId;

  String get label {
    final group = stairsGroupId;
    if (group == null || group.isEmpty) return 'лестница';
    final base = fromStairs.label.isEmpty
        ? 'лестница $group'
        : fromStairs.label;
    return base;
  }

  @override
  String toString() => '$label: $fromFloor → $toFloor';
}

/// Результат поиска маршрута.
class RouteResult {
  const RouteResult({
    required this.steps,
    required this.cost,
    required this.distanceMeters,
    required this.stairsMeters,
    required this.transitions,
    required this.eta,
  });

  final List<RouteStep> steps;

  /// Полная стоимость пути в метрах (коридоры + подъёмы по лестницам).
  final double cost;

  /// Длина пути в метрах: горизонталь плюс эквивалент подъёма по лестницам.
  final double distanceMeters;

  /// Часть [distanceMeters], приходящаяся на лестницы.
  final double stairsMeters;

  final List<RouteTransition> transitions;

  /// Оценка времени в пути.
  final Duration eta;

  int get transitionCount => transitions.length;

  bool get isEmpty => steps.length < 2;

  /// Этажи, через которые проходит маршрут (по порядку, без повторов).
  List<int> get floors {
    final result = <int>[];
    for (final step in steps) {
      if (result.isEmpty || result.last != step.floor) {
        result.add(step.floor);
      }
    }
    return result;
  }
}

/// Поиск кратчайшего пути по графу здания (A*).
///
/// Все стоимости в графе — метры: длины коридоров пересчитаны по масштабу
/// этажа (`metersPerPixel` из JSON), подъём на этаж стоит
/// [NavGraph.stairsMetersPerFloor] за этаж.
class RouteBuilder {
  RouteBuilder(this.graph, {this.walkingSpeed = defaultWalkingSpeed});

  static const double defaultWalkingSpeed = 1.25;

  final NavGraph graph;
  final double walkingSpeed;

  RouteResult? findRoute({
    required int startFloor,
    required String startNodeId,
    required int endFloor,
    required String endNodeId,
  }) {
    final start = NavSpot(startFloor, startNodeId);
    final end = NavSpot(endFloor, endNodeId);
    final startNode = graph.nodeAt(start);
    final endNode = graph.nodeAt(end);
    if (startNode == null || endNode == null) return null;

    if (start == end) {
      return RouteResult(
        steps: <RouteStep>[RouteStep(floor: start.floor, node: startNode)],
        cost: 0,
        distanceMeters: 0,
        stairsMeters: 0,
        transitions: const <RouteTransition>[],
        eta: Duration.zero,
      );
    }

    final best = <NavSpot, double>{start: 0.0};
    final cameFrom = <NavSpot, _Arrival>{};
    final heap = _MinHeap();
    var sequence = 0;

    heap.push(_QueueEntry(_heuristic(start, end), 0, start, sequence++));

    while (heap.isNotEmpty) {
      final current = heap.pop();
      final known = best[current.spot];
      if (known == null || current.g > known) continue; // устаревшая запись
      if (current.spot == end) {
        return _buildResult(start, end, cameFrom, current.g);
      }

      for (final link in graph.linksFrom(current.spot)) {
        final target = graph.nodeAt(link.to);
        if (target == null) continue;
        // Через аудитории и входы проходить нельзя — только входить в них.
        final isTarget = link.to == end;
        if (!isTarget && !target.isTransit) continue;

        final candidate = current.g + link.cost;
        if (candidate < (best[link.to] ?? double.infinity)) {
          best[link.to] = candidate;
          cameFrom[link.to] = _Arrival(from: current.spot, link: link);
          heap.push(
            _QueueEntry(
              candidate + _heuristic(link.to, end),
              candidate,
              link.to,
              sequence++,
            ),
          );
        }
      }
    }
    return null;
  }

  /// Нижняя оценка оставшейся стоимости. Допустимая: путь не короче
  /// прямого расстояния, а каждый переход между этажами стоит полную цену.
  double _heuristic(NavSpot from, NavSpot to) {
    if (from.floor != to.floor) {
      return graph.stairsMetersPerFloor * (from.floor - to.floor).abs();
    }
    final a = graph.nodeAt(from);
    final b = graph.nodeAt(to);
    if (a == null || b == null) return 0;
    return a.position.distanceTo(b.position) * graph.scaleFor(from.floor);
  }

  RouteResult _buildResult(
    NavSpot start,
    NavSpot end,
    Map<NavSpot, _Arrival> cameFrom,
    double totalCost,
  ) {
    final states = <NavSpot>[end];
    var cursor = end;
    while (cursor != start) {
      final arrival = cameFrom[cursor];
      if (arrival == null) break;
      cursor = arrival.from;
      states.insert(0, cursor);
    }

    final steps = <RouteStep>[];
    final transitions = <RouteTransition>[];
    var stairsMeters = 0.0;

    for (var i = 0; i < states.length; i++) {
      final spot = states[i];
      final node = graph.nodeAt(spot);
      if (node == null) continue;

      final arrival = i == 0 ? null : cameFrom[spot];
      final isTransition = arrival?.link.stairs ?? false;

      steps.add(
        RouteStep(
          floor: spot.floor,
          node: node,
          isTransition: isTransition,
          segmentCost: arrival?.link.cost ?? 0,
        ),
      );

      if (arrival == null) continue;
      if (arrival.link.stairs) {
        stairsMeters += arrival.link.cost;
        final fromStairs = graph.nodeAt(arrival.from);
        if (fromStairs != null) {
          transitions.add(
            RouteTransition(
              fromFloor: arrival.from.floor,
              toFloor: spot.floor,
              fromStairs: fromStairs,
              toStairs: node,
              stairsGroupId: arrival.link.stairsGroupId,
            ),
          );
        }
      }
    }

    // Стоимость пути уже в метрах: и коридоры, и лестницы.
    final distanceMeters = totalCost;
    final seconds = distanceMeters / walkingSpeed;

    return RouteResult(
      steps: steps,
      cost: totalCost,
      distanceMeters: distanceMeters,
      stairsMeters: stairsMeters,
      transitions: transitions,
      eta: Duration(seconds: seconds.round()),
    );
  }
}

class _Arrival {
  const _Arrival({required this.from, required this.link});

  final NavSpot from;
  final NavLink link;
}

class _QueueEntry {
  const _QueueEntry(this.priority, this.g, this.spot, this.sequence);

  final double priority;
  final double g;
  final NavSpot spot;
  final int sequence;
}

/// Двоичная min-куча с детерминированным tie-break по порядку вставки.
///
/// Собственная реализация, чтобы не добавлять зависимость и не хранить
/// в множестве элементы с изменяющимся ключом (это ломало A*).
class _MinHeap {
  final List<_QueueEntry> _items = <_QueueEntry>[];

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  void push(_QueueEntry entry) {
    _items.add(entry);
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (!_less(_items[index], _items[parent])) break;
      _swap(index, parent);
      index = parent;
    }
  }

  _QueueEntry pop() {
    final top = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var index = 0;
      while (true) {
        final left = 2 * index + 1;
        final right = 2 * index + 2;
        var smallest = index;
        if (left < _items.length && _less(_items[left], _items[smallest])) {
          smallest = left;
        }
        if (right < _items.length && _less(_items[right], _items[smallest])) {
          smallest = right;
        }
        if (smallest == index) break;
        _swap(index, smallest);
        index = smallest;
      }
    }
    return top;
  }

  static bool _less(_QueueEntry a, _QueueEntry b) => a.priority != b.priority
      ? a.priority < b.priority
      : a.sequence < b.sequence;

  void _swap(int i, int j) {
    final tmp = _items[i];
    _items[i] = _items[j];
    _items[j] = tmp;
  }
}
