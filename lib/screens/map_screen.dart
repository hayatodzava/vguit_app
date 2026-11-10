import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/map_models.dart';
import '../models/map_transform.dart';
import '../services/map_data.dart';
import '../services/map_loader.dart';
import '../services/route_builder.dart';
import 'search_picker_dialog.dart';

/// Бледно-красный цвет линии маршрута.
const Color _routeColor = Color(0xFFE57373);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Радиус попадания по узлу при тапе (экранные пиксели).
  static const double _tapRadiusPixels = 24;

  MapData? _data;
  String? _loadError;
  bool _loading = true;

  int _currentFloor = 1;
  MapNode? _fromNode;
  MapNode? _toNode;
  int? _fromFloor;
  int? _toFloor;
  RouteResult? _route;
  bool _panelOpen = true;

  // Текущий вид.
  double _scale = 1.0;
  double _rotation = 0.0;
  Offset _offset = Offset.zero;

  // Состояние на начало жеста.
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _baseFocalMap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await MapLoader.loadAll();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        if (data.floorsByNumber.containsKey(1)) {
          _currentFloor = 1;
        } else if (data.floors.isNotEmpty) {
          _currentFloor = data.floors.first.floor;
        }
        final entrance =
            data.entranceOn(1) ??
            (data.entrances.isNotEmpty ? data.entrances.first : null);
        if (entrance != null) {
          _fromNode = entrance.node;
          _fromFloor = entrance.floor;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Не удалось загрузить карту: $error';
        _loading = false;
      });
    }
  }

  // ─── Состояние маршрута ───

  bool get _bothSelected =>
      _fromNode != null &&
      _toNode != null &&
      _fromFloor != null &&
      _toFloor != null;

  void _recalculateRoute() {
    final data = _data;
    if (data == null || !_bothSelected) {
      _route = null;
      return;
    }
    final result = data.routeBuilder.findRoute(
      startFloor: _fromFloor!,
      startNodeId: _fromNode!.id,
      endFloor: _toFloor!,
      endNodeId: _toNode!.id,
    );
    _route = result;
    if (result != null && result.steps.isNotEmpty) {
      _currentFloor = result.steps.first.floor;
      _resetViewValues();
    }
  }

  void _resetViewValues() {
    _scale = 1.0;
    _rotation = 0.0;
    _offset = Offset.zero;
  }

  void _swapEndpoints() {
    if (!_bothSelected) return;
    setState(() {
      final node = _fromNode;
      final floor = _fromFloor;
      _fromNode = _toNode;
      _fromFloor = _toFloor;
      _toNode = node;
      _toFloor = floor;
      _recalculateRoute();
    });
  }

  // ─── Выбор точек ───

  Future<void> _pickFrom() async {
    final data = _data;
    if (data == null) return;
    final chosen = await showSearchPickerDialog<({int floor, MapNode node})>(
      context: context,
      title: 'Откуда идём',
      items: data.visiblePoints,
      hint: 'Поиск аудитории',
      labelBuilder: (item) =>
          '${item.node.displayLabel}  (${MapData.floorLabel(item.floor)})',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _fromNode = chosen.node;
      _fromFloor = chosen.floor;
      _recalculateRoute();
    });
  }

  Future<void> _pickTo() async {
    final data = _data;
    if (data == null) return;
    final chosen = await showSearchPickerDialog<({int floor, MapNode node})>(
      context: context,
      title: 'Куда идём',
      items: data.visiblePoints,
      hint: 'Поиск аудитории',
      labelBuilder: (item) =>
          '${item.node.displayLabel}  (${MapData.floorLabel(item.floor)})',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _toNode = chosen.node;
      _toFloor = chosen.floor;
      _recalculateRoute();
    });
  }

  // ─── Жесты ───

  void _onScaleStart(ScaleStartDetails details, MapTransform transform) {
    _baseScale = _scale;
    _baseRotation = _rotation;
    _baseFocalMap = transform.toMap(details.localFocalPoint);
  }

  void _onScaleUpdate(
    ScaleUpdateDetails details,
    MapTransform transform,
    Size viewport,
  ) {
    final nextScale = (_baseScale * details.scale)
        .clamp(MapTransform.minScale, MapTransform.maxScale)
        .toDouble();
    final nextRotation = _baseRotation + details.rotation;
    final next = transform
        .copyWith(scale: nextScale, rotation: nextRotation)
        .anchor(mapPoint: _baseFocalMap, screenPoint: details.localFocalPoint);
    setState(() {
      _scale = next.scale;
      _rotation = next.rotation;
      _offset = _clampOffset(next.offset, viewport);
    });
  }

  Offset _clampOffset(Offset offset, Size viewport) {
    final maxX = viewport.width * 2.5;
    final maxY = viewport.height * 2.5;
    return Offset(
      offset.dx.clamp(-maxX, maxX).toDouble(),
      offset.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  void _onTapUp(TapUpDetails details, MapTransform transform, MapFloor floor) {
    final mapPoint = transform.toMap(details.localPosition);
    final radius = _tapRadiusPixels / transform.total;

    MapNode? closest;
    var bestDistance = radius;
    for (final node in floor.nodes) {
      if (!node.isVisible || node.isStairs) continue;
      final distance = node.position.distanceTo(
        MapPoint(mapPoint.dx, mapPoint.dy),
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        closest = node;
      }
    }
    if (closest == null) return;
    _showNodeActions(closest, floor.floor);
  }

  Future<void> _showNodeActions(MapNode node, int floor) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text(node.displayLabel),
              subtitle: Text(MapData.floorLabel(floor)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.trip_origin),
              title: const Text('Идти отсюда'),
              onTap: () => Navigator.of(sheetContext).pop('from'),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: const Text('Идти сюда'),
              onTap: () => Navigator.of(sheetContext).pop('to'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() {
      if (action == 'from') {
        _fromNode = node;
        _fromFloor = floor;
      } else {
        _toNode = node;
        _toFloor = floor;
      }
      _recalculateRoute();
    });
  }

  void _zoomBy(double factor) {
    final data = _data;
    final floor = data?.floorsByNumber[_currentFloor];
    if (floor == null) return;
    final viewport = _lastViewport;
    if (viewport == null) return;
    final transform = _transformFor(floor, viewport).zoomedBy(factor);
    setState(() {
      _scale = transform.scale;
      _rotation = transform.rotation;
      _offset = transform.offset;
    });
  }

  void _resetView() {
    setState(_resetViewValues);
  }

  Size? _lastViewport;

  MapTransform _transformFor(MapFloor floor, Size viewport) => MapTransform(
    viewportSize: viewport,
    imageSize: Size(floor.width, floor.height),
    scale: _scale,
    rotation: _rotation,
    offset: _offset,
  );

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
          if (data != null && data.hasIssues)
            IconButton(
              icon: const Icon(Icons.report_problem_outlined),
              tooltip: 'Замечания к данным карты',
              onPressed: _showDiagnostics,
            ),
          IconButton(
            icon: Icon(_panelOpen ? Icons.expand_more : Icons.expand_less),
            tooltip: _panelOpen ? 'Скрыть панель' : 'Показать панель',
            onPressed: () => setState(() => _panelOpen = !_panelOpen),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _message(_loadError!, icon: Icons.error_outline);
    }
    final data = _data;
    if (data == null || data.isEmpty) {
      return _message(
        'Планы этажей не загружены.\n'
        '${data?.errors.take(3).join('\n') ?? ''}',
        icon: Icons.map_outlined,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _lastViewport = viewport;
        final floor = data.floorsByNumber[_currentFloor];
        if (floor == null) {
          return _message('Нет плана для этажа $_currentFloor');
        }
        final transform = _transformFor(floor, viewport);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) => _onScaleStart(details, transform),
                onScaleUpdate: (details) =>
                    _onScaleUpdate(details, transform, viewport),
                onTapUp: (details) => _onTapUp(details, transform, floor),
                child: _buildMapView(transform, floor),
              ),
            ),
            _buildFloorSwitcher(data),
            if (_panelOpen) _buildPanel(),
          ],
        );
      },
    );
  }

  Widget _buildMapView(MapTransform transform, MapFloor floor) {
    final route = _route;
    // Маршрут на текущем этаже может состоять из нескольких участков:
    // если он уходит на другой этаж и возвращается, это разные линии.
    final polylines = <List<Offset>>[];
    Offset? startPoint;
    Offset? endPoint;

    if (route != null) {
      var current = <Offset>[];
      for (final step in route.steps) {
        if (step.floor != floor.floor) {
          if (current.length > 1) polylines.add(current);
          current = <Offset>[];
          continue;
        }
        current.add(transform.toScreen(Offset(step.node.x, step.node.y)));
      }
      if (current.length > 1) polylines.add(current);
    }

    // Точки «откуда/куда» показываем сразу после выбора, ещё до маршрута.
    if (_fromNode != null && _fromFloor == floor.floor) {
      startPoint = transform.toScreen(Offset(_fromNode!.x, _fromNode!.y));
    }
    if (_toNode != null && _toFloor == floor.floor) {
      endPoint = transform.toScreen(Offset(_toNode!.x, _toNode!.y));
    }

    final labels = _buildLabels(transform, floor);
    final stairPositions = <Offset>[
      for (final node in floor.nodes)
        if (node.isStairs) transform.toScreen(Offset(node.x, node.y)),
    ];

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: transform.toMatrix(),
                  child: SizedBox(
                    width: floor.width,
                    height: floor.height,
                    child: SvgPicture.asset(floor.svgAsset, fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RoutePainter(
                  polylines: polylines,
                  startPoint: startPoint,
                  endPoint: endPoint,
                  color: _routeColor,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StairsPainter(positions: stairPositions),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _LabelPainter(labels: labels)),
            ),
          ),
        ],
      ),
    );
  }

  List<_MapLabel> _buildLabels(MapTransform transform, MapFloor floor) {
    final labels = <_MapLabel>[];
    for (final node in floor.nodes) {
      // Лестницы подписью не подписываем — на их месте рисуется иконка.
      if (!node.isVisible || node.isStairs) continue;
      final isEndpoint =
          (_fromFloor == floor.floor && identical(node, _fromNode)) ||
          (_toFloor == floor.floor && identical(node, _toNode));
      final priority = isEndpoint
          ? 0
          : (node.type == MapNodeType.entrance ? 1 : 3);
      labels.add(
        _MapLabel(
          text: node.displayLabel,
          position: transform.toScreen(Offset(node.x, node.y)),
          priority: priority,
          emphasis: isEndpoint,
        ),
      );
    }
    labels.sort((a, b) => a.priority.compareTo(b.priority));
    return labels;
  }

  Widget _buildFloorSwitcher(MapData data) {
    final floors = data.floorNumbers.toList()..sort();
    final routeFloors = _route?.floors.toSet() ?? const <int>{};

    return Positioned(
      right: 12,
      top: 12,
      child: Column(
        children: [
          for (final floorNumber in floors.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _floorButton(
                floorNumber,
                active: floorNumber == _currentFloor,
                onRoute: routeFloors.contains(floorNumber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _floorButton(
    int floorNumber, {
    required bool active,
    required bool onRoute,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _currentFloor = floorNumber),
        child: SizedBox(
          width: 44,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                floorNumber == -1 ? '−1' : '$floorNumber',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: active ? scheme.onPrimary : null,
                ),
              ),
              if (onRoute && !active)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final route = _route;
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.trip_origin, size: 18),
                    label: Text(
                      _fromNode?.displayLabel ?? 'Откуда',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _pickFrom,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Поменять местами',
                  onPressed: _bothSelected ? _swapEndpoints : null,
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.place, size: 18),
                    label: Text(
                      _toNode?.displayLabel ?? 'Куда',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _pickTo,
                  ),
                ),
              ],
            ),
            if (route != null) ...[
              const SizedBox(height: 8),
              if (route.isEmpty)
                const Text('Начало и конец совпадают')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _infoChip(
                      Icons.straighten,
                      '≈ ${_formatDistance(route.distanceMeters)}',
                    ),
                    _infoChip(Icons.schedule, _formatDuration(route.eta)),
                    if (route.transitionCount > 0)
                      _infoChip(
                        Icons.stairs,
                        '${route.transitionCount} '
                        '${_pluralTransitions(route.transitionCount)}',
                      ),
                    for (final transition in route.transitions)
                      ActionChip(
                        avatar: const Icon(Icons.stairs, size: 16),
                        label: Text(
                          '${transition.label}: '
                          '${transition.fromFloor} → ${transition.toFloor}',
                        ),
                        onPressed: () =>
                            setState(() => _currentFloor = transition.toFloor),
                      ),
                  ],
                ),
            ] else if (_bothSelected) ...[
              const SizedBox(height: 8),
              Text('Маршрут не найден', style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _smallButton(
                  Icons.zoom_out,
                  'Уменьшить',
                  () => _zoomBy(1 / 1.4),
                ),
                const SizedBox(width: 4),
                _smallButton(Icons.zoom_in, 'Увеличить', () => _zoomBy(1.4)),
                const SizedBox(width: 4),
                _smallButton(Icons.zoom_out_map, 'Сбросить вид', _resetView),
                const Spacer(),
                if (_rotation != 0)
                  _smallButton(
                    Icons.explore_outlined,
                    'Выровнять',
                    () => setState(() => _rotation = 0),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton.outlined(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _message(String text, {IconData icon = Icons.info_outline}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showDiagnostics() {
    final data = _data;
    if (data == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Данные карты'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView(
            children: [
              if (data.errors.isNotEmpty) ...[
                Text(
                  'Ошибки',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
                for (final issue in data.errors)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                    title: Text(issue),
                  ),
                const SizedBox(height: 8),
              ],
              if (data.warnings.isNotEmpty) ...[
                const Text(
                  'Предупреждения',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final issue in data.warnings)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(issue),
                  ),
              ],
              if (!data.hasIssues) const Text('Замечаний нет'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // ─── Форматирование ───

  String _formatDistance(double meters) {
    if (meters < 5) return 'рядом';
    if (meters < 1000) return '${(meters / 10).round() * 10} м';
    return '${(meters / 100).round() / 10} км';
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) return 'меньше минуты';
    if (duration.inMinutes < 60) return '${duration.inMinutes} мин';
    return '${duration.inHours} ч ${duration.inMinutes % 60} мин';
  }

  String _pluralTransitions(int count) {
    final mod100 = count % 100;
    final mod10 = count % 10;
    if (mod100 >= 11 && mod100 <= 14) return 'переходов';
    if (mod10 == 1) return 'переход';
    if (mod10 >= 2 && mod10 <= 4) return 'перехода';
    return 'переходов';
  }
}

/// Подпись на плане.
@immutable
class _MapLabel {
  const _MapLabel({
    required this.text,
    required this.position,
    required this.priority,
    this.emphasis = false,
  });

  final String text;
  final Offset position;
  final int priority;
  final bool emphasis;

  @override
  bool operator ==(Object other) =>
      other is _MapLabel &&
      other.text == text &&
      other.position == position &&
      other.priority == priority &&
      other.emphasis == emphasis;

  @override
  int get hashCode => Object.hash(text, position, priority, emphasis);
}

/// Подписи рисуются в экранных координатах, чтобы оставаться читаемыми
/// при любом зуме. Пересекающиеся подписи отбрасываются по приоритету.
class _LabelPainter extends CustomPainter {
  _LabelPainter({required this.labels});

  final List<_MapLabel> labels;

  static final Map<String, List<TextPainter>> _cache =
      <String, List<TextPainter>>{};

  static List<TextPainter> _painters(String text, bool emphasis) {
    final key = '${emphasis ? 'e' : 'n'}:$text';
    return _cache.putIfAbsent(key, () {
      final style = TextStyle(
        fontSize: emphasis ? 12 : 10,
        fontWeight: FontWeight.w600,
      );
      final stroke = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..color = Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final fill = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return <TextPainter>[stroke, fill];
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final placed = <Rect>[];
    for (final label in labels) {
      final painters = _painters(label.text, label.emphasis);
      final textSize = painters.last.size;
      final rect = Rect.fromCenter(
        center: label.position,
        width: textSize.width + 4,
        height: textSize.height + 2,
      );
      if (!label.emphasis && placed.any((other) => other.overlaps(rect))) {
        continue;
      }
      placed.add(rect);
      final origin =
          label.position - Offset(textSize.width / 2, textSize.height / 2);
      for (final painter in painters) {
        painter.paint(canvas, origin);
      }
    }
  }

  @override
  bool shouldRepaint(_LabelPainter oldDelegate) =>
      !listEquals(oldDelegate.labels, labels);
}

/// Иконки лестниц: подписи у лестниц не рисуются, только значок на месте узла.
class _StairsPainter extends CustomPainter {
  _StairsPainter({required this.positions});

  final List<Offset> positions;

  static const double _radius = 10;
  static TextPainter? _cachedIcon;

  static TextPainter get _icon {
    return _cachedIcon ??= (TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.stairs.codePoint),
        style: TextStyle(
          fontSize: 14,
          fontFamily: Icons.stairs.fontFamily,
          package: Icons.stairs.fontPackage,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black54;
    final icon = _icon;
    for (final position in positions) {
      canvas.drawCircle(position, _radius, fill);
      canvas.drawCircle(position, _radius, border);
      icon.paint(canvas, position - Offset(icon.width / 2, icon.height / 2));
    }
  }

  @override
  bool shouldRepaint(_StairsPainter oldDelegate) =>
      !listEquals(oldDelegate.positions, positions);
}

/// Линия маршрута в экранных координатах.
class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.polylines,
    required this.color,
    this.startPoint,
    this.endPoint,
  });

  final List<List<Offset>> polylines;
  final Color color;
  final Offset? startPoint;
  final Offset? endPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final routePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final points in polylines) {
      if (points.length < 2) continue;
      final path = _smoothPath(points);
      canvas.drawPath(path, outlinePaint);
      canvas.drawPath(path, routePaint);
    }

    _drawMarker(canvas, startPoint, Colors.green.shade700);
    _drawMarker(canvas, endPoint, color);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    const tension = 0.12;
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[0] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) * tension / 2,
        p1.dy + (p2.dy - p0.dy) * tension / 2,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) * tension / 2,
        p2.dy - (p3.dy - p1.dy) * tension / 2,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawMarker(Canvas canvas, Offset? point, Color color) {
    if (point == null) return;
    canvas.drawCircle(point, 9, Paint()..color = Colors.white);
    canvas.drawCircle(point, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      !_samePolylines(oldDelegate.polylines, polylines) ||
      oldDelegate.color != color ||
      oldDelegate.startPoint != startPoint ||
      oldDelegate.endPoint != endPoint;

  static bool _samePolylines(List<List<Offset>> a, List<List<Offset>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }
}
