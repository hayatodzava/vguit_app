import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/schedule.dart';
import '../services/net.dart';
import '../services/schedule_cache.dart';
import '../services/schedule_parser.dart';
import '../services/schedule_preferences.dart';
import '../services/schedule_sources.dart';
import '../widgets/error_banner.dart';
import '../widgets/error_dialog.dart';
import 'course_drawer.dart';
import 'teacher_schedule_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const List<String> _courses = [
    '1 курс',
    '2 курс',
    '3 курс',
    '4 курс',
    '5 курс + магистры',
  ];

  // Геометрия таблицы.
  static const double _dayColWidth = 25;
  static const double _timeColWidth = 50;
  static const double _groupColWidth = 130;
  static const double _headerHeight = 48;
  static const double _cellPadding = 12;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScheduleCache _cache = ScheduleCache();

  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _rowsVertical = ScrollController();
  final ScrollController _daysVertical = ScrollController();

  int _scheduleTab = 0;

  String _selectedFaculty = 'УИТС';
  String _selectedCourse = '1 курс';

  /// Выбранная группа для показа; null — все группы курса.
  String? _selectedGroup;

  bool _isLoading = false;
  AppException? _error;
  ScheduleData? _schedule;
  DateTime? _lastUpdated;
  Uint8List? _excelBytes;

  /// Разобранные листы: «факультет|курс» → расписание.
  /// Переключение курса больше не перечитывает файл.
  final Map<String, ScheduleData> _parsed = <String, ScheduleData>{};

  /// Все группы факультета: «группа → курс». Заполняется по требованию,
  /// потому что для этого нужно разобрать весь файл.
  Map<String, String>? _groupCatalog;
  bool _loadingCatalog = false;

  List<_RowSpec> _rows = const <_RowSpec>[];
  List<double> _rowHeights = const <double>[];
  List<_DayBlock> _dayBlocks = const <_DayBlock>[];
  double _totalWidth = 0;

  /// Ширина колонки группы, под которую считались высоты строк.
  /// Для одной растянутой группы она равна ширине экрана.
  double _layoutColumnWidth = _groupColWidth;

  @override
  void initState() {
    super.initState();
    _rowsVertical.addListener(_syncVerticalScroll);
    _restoreAndLoad();
  }

  /// Поднимает сохранённые курс и группу, затем грузит расписание.
  Future<void> _restoreAndLoad() async {
    try {
      final prefs = const SchedulePreferences();
      final course = await prefs.loadCourse();
      final group = await prefs.loadGroup();
      if (!mounted) return;
      setState(() {
        if (course != null && _courses.contains(course)) {
          _selectedCourse = course;
        }
        // Группа применится в _applySchedule, если она есть на этом листе.
        _selectedGroup = group;
      });
    } catch (_) {
      // Настройки недоступны — просто открываем значения по умолчанию.
    }
    await _loadFromCacheOrServer();
  }

  Future<void> _saveStudentsPreferences() async {
    try {
      await const SchedulePreferences().saveStudents(
        course: _selectedCourse,
        group: _selectedGroup,
      );
    } catch (_) {
      // Не критично: в следующий раз откроется вид по умолчанию.
    }
  }

  @override
  void dispose() {
    _rowsVertical.removeListener(_syncVerticalScroll);
    _bodyHorizontal.dispose();
    _rowsVertical.dispose();
    _daysVertical.dispose();
    super.dispose();
  }

  /// Левая колонка (дни и время) едет вместе со строками.
  void _syncVerticalScroll() {
    if (!_daysVertical.hasClients) return;
    final target = _rowsVertical.offset;
    if ((_daysVertical.offset - target).abs() < 0.5) return;
    final max = _daysVertical.position.maxScrollExtent;
    _daysVertical.jumpTo(target.clamp(0.0, max).toDouble());
  }

  // ─── Загрузка ───

  Future<void> _loadFromCacheOrServer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final cachedBytes = await _cache.loadBytes(_selectedFaculty);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        _excelBytes = cachedBytes;
        _lastUpdated = await _cache.loadUpdatedAt(_selectedFaculty);
        await _parseCurrent();
      } else {
        await _fetchFromServer();
      }
    } catch (error) {
      _handleError(error, 'Не удалось загрузить расписание');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFromServer() async {
    final bytes = await ScheduleSources.download(_selectedFaculty);

    _excelBytes = bytes;
    _lastUpdated = DateTime.now();
    await _cache.saveBytes(_selectedFaculty, bytes);
    await _parseCurrent();
  }

  /// Разбор книги в отдельном изоляте + кэш результата по курсу.
  Future<void> _parseCurrent() async {
    final bytes = _excelBytes;
    if (bytes == null) return;

    final key = '$_selectedFaculty|$_selectedCourse';
    final cached = _parsed[key];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _applySchedule(cached));
      return;
    }

    final data = await compute(
      parseScheduleInBackground,
      ScheduleParseRequest(
        bytes: bytes,
        sheetName: _selectedCourse,
        faculty: _selectedFaculty,
      ),
    );

    _parsed[key] = data;
    if (!mounted) return;
    setState(() {
      _applySchedule(data);
      _error = null;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _parsed.clear();
      await _fetchFromServer();
      // Файл обновился — каталог групп мог измениться.
      if (mounted) setState(() => _groupCatalog = null);
    } catch (error) {
      _handleError(error, 'Не удалось обновить расписание');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleError(Object error, String title) {
    final exception = AppException.from(error);
    if (!mounted) return;
    setState(() => _error = exception);
    showErrorDialog(context, title: title, error: exception);
  }

  // ─── Выбор факультета и курса ───

  Future<void> _onFacultyChanged(String? value) async {
    if (value == null || value == _selectedFaculty) return;
    setState(() {
      _selectedFaculty = value;
      _excelBytes = null;
      _schedule = null;
      _lastUpdated = null;
      _error = null;
      // У другого факультета свои группы — выбор и каталог сбрасываем.
      _selectedGroup = null;
      _groupCatalog = null;
    });
    await _saveStudentsPreferences();
    await _loadFromCacheOrServer();
  }

  Future<void> _onCourseSelected(String course) async {
    if (course == _selectedCourse) return;
    setState(() {
      _selectedCourse = course;
      _error = null;
    });
    try {
      await _parseCurrent();
      await _saveStudentsPreferences();
    } catch (error) {
      _handleError(error, 'Не удалось разобрать расписание');
    }
  }

  // ─── Подготовка таблицы ───

  /// Колонки, которые реально показываются: все группы или выбранная одна.
  List<GroupInfo> get _visibleGroupCols {
    final data = _schedule;
    if (data == null) return const <GroupInfo>[];
    final selected = _selectedGroup;
    if (selected == null) return data.groupCols;
    return data.groupCols
        .where((group) => group.name == selected)
        .toList(growable: false);
  }

  /// Все группы факультета для выбора в боковом меню.
  ///
  /// Пока каталог не построен — показываем группы текущего курса.
  List<String> get _groupNames {
    final catalog = _groupCatalog;
    if (catalog != null && catalog.isNotEmpty) {
      final names = catalog.keys.toList()..sort();
      return List<String>.unmodifiable(names);
    }
    return _schedule?.groupCols
            .map((group) => group.name)
            .toList(growable: false) ??
        const <String>[];
  }

  /// Строит каталог «группа → курс» по всему файлу факультета.
  Future<void> _ensureGroupCatalog() async {
    if (_groupCatalog != null || _loadingCatalog) return;

    setState(() => _loadingCatalog = true);
    try {
      // Если расписание ещё не загружено в память, берём файл из кэша.
      var bytes = _excelBytes;
      if (bytes == null) {
        bytes = await _cache.loadBytes(_selectedFaculty);
        _excelBytes = bytes;
      }
      if (bytes == null) return;

      final catalog = await compute(ScheduleSources.groupCourses, bytes);
      if (!mounted) return;
      setState(() => _groupCatalog = catalog);
    } catch (error) {
      if (!mounted) return;
      showMessageSnackBar(
        context,
        'Не удалось получить список групп: ${AppException.from(error).message}',
      );
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  void _applySchedule(ScheduleData data) {
    _schedule = data;
    // Если выбранной группы нет на новом листе — показываем все.
    if (_selectedGroup != null &&
        !data.groupCols.any((group) => group.name == _selectedGroup)) {
      _selectedGroup = null;
    }
    _rebuildGeometry();
  }

  /// Выбор группы. Если группа с другого курса — переключаемся на него.
  Future<void> _onGroupSelected(String? group) async {
    if (group == _selectedGroup) return;

    if (group != null) {
      final course = _groupCatalog?[group];
      if (course != null && course != _selectedCourse) {
        setState(() => _selectedCourse = course);
        try {
          await _parseCurrent();
        } catch (error) {
          _handleError(error, 'Не удалось разобрать расписание');
          return;
        }
        if (!mounted) return;
      }
    }

    setState(() {
      _selectedGroup = group;
      _rebuildGeometry();
    });
    await _saveStudentsPreferences();
  }

  /// Пересчитывает строки, высоты и ширину под текущий набор колонок.
  void _rebuildGeometry() {
    final data = _schedule;
    if (data == null) {
      _rows = const <_RowSpec>[];
      _rowHeights = const <double>[];
      _dayBlocks = const <_DayBlock>[];
      _totalWidth = 0;
      return;
    }

    final groups = _visibleGroupCols;
    final rows = <_RowSpec>[];
    for (final dayEntry in data.lessons.entries) {
      final times = dayEntry.value;
      final sortedTimes = data.timeSlots
          .where((time) => times.containsKey(time))
          .toList();
      for (var i = 0; i < sortedTimes.length; i++) {
        rows.add(
          _RowSpec(
            day: i == 0 ? dayEntry.key : '',
            time: sortedTimes[i],
            groupMap: times[sortedTimes[i]]!,
          ),
        );
      }
    }

    final heights = <double>[
      for (final row in rows)
        _measureRow(row, groups, _layoutColumnWidth - _cellPadding),
    ];

    // Блоки дней: одна вертикальная подпись дня на весь блок.
    final blocks = <_DayBlock>[];
    var index = 0;
    while (index < rows.length) {
      var count = 1;
      while (index + count < rows.length &&
          rows[index + count].day.trim().isEmpty) {
        count++;
      }
      var height = 0.0;
      for (var i = 0; i < count; i++) {
        height += heights[index + i];
      }
      blocks.add(
        _DayBlock(
          day: rows[index].day,
          startIndex: index,
          rowCount: count,
          height: height,
        ),
      );
      index += count;
    }

    _rows = rows;
    _rowHeights = heights;
    _dayBlocks = blocks;
    _totalWidth = groups.fold<double>(
      0,
      (sum, group) =>
          sum + (group.hasSubgroups ? _groupColWidth * 2 : _groupColWidth),
    );
  }

  double _measureRow(_RowSpec row, List<GroupInfo> groups, double columnWidth) {
    const style = TextStyle(fontSize: 11);
    final scaler = MediaQuery.textScalerOf(context);
    final width = math.max(columnWidth, 40.0);

    var top = 20.0;
    var bottom = 20.0;

    for (final group in groups) {
      final cell = row.groupMap[group.name];
      if (cell == null) continue;
      if (group.hasSubgroups) {
        for (final text in [cell.sub1Num, cell.sub2Num]) {
          top = math.max(top, _measureText(text, width, style, scaler));
        }
        for (final text in [cell.sub1Den, cell.sub2Den]) {
          bottom = math.max(bottom, _measureText(text, width, style, scaler));
        }
      } else {
        top = math.max(top, _measureText(cell.numerator, width, style, scaler));
        bottom = math.max(
          bottom,
          _measureText(cell.denominator, width, style, scaler),
        );
      }
    }

    return top + bottom + 1 + 4 + _cellPadding + 6;
  }

  double _measureText(
    String text,
    double width,
    TextStyle style,
    TextScaler scaler,
  ) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: null,
    )..layout(maxWidth: width);
    return painter.height;
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          if (_scheduleTab == 0)
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Курс и группа',
              onPressed: () {
                _scaffoldKey.currentState?.openEndDrawer();
                // Список групп всего факультета строится по файлу —
                // делаем это при открытии меню, чтобы не тормозить экран.
                _ensureGroupCatalog();
              },
            ),
        ],
      ),
      endDrawer: _scheduleTab == 0
          ? CourseDrawer(
              selectedCourse: _selectedCourse,
              courses: _courses,
              groups: _groupNames,
              groupsLoading: _loadingCatalog,
              groupCourses: _groupCatalog,
              selectedGroup: _selectedGroup,
              onSelected: (course) {
                Navigator.of(context).pop();
                _onCourseSelected(course);
              },
              onGroupSelected: (group) {
                Navigator.of(context).pop();
                _onGroupSelected(group);
              },
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Студенты'),
                  icon: Icon(Icons.group),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Преподаватели'),
                  icon: Icon(Icons.person),
                ),
              ],
              selected: {_scheduleTab},
              onSelectionChanged: (selection) {
                setState(() => _scheduleTab = selection.first);
              },
            ),
          ),
          Expanded(
            child: _scheduleTab == 0
                ? _buildStudentsSchedule()
                : const TeacherScheduleScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsSchedule() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedFaculty,
                  key: ValueKey('faculty-$_selectedFaculty'),
                  decoration: const InputDecoration(
                    labelText: 'Факультет',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ScheduleSources.faculties
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: _isLoading ? null : _onFacultyChanged,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refresh,
                tooltip: 'Обновить с сервера',
              ),
            ],
          ),
        ),
        if (_schedule != null) _buildStatusRow(_schedule!),
        if (_error != null && _schedule != null)
          ErrorBanner(error: _error!, onRetry: _refresh),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildStatusRow(ScheduleData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.school_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _selectedGroup == null
                  ? '${data.faculty} • ${data.course}'
                  : '${data.faculty} • ${data.course} • '
                        'группа $_selectedGroup',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (_lastUpdated != null)
            Text(
              _formatDt(_lastUpdated!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_schedule == null) {
      if (_error != null) {
        return _buildErrorState();
      }
      return const Center(
        child: Text('Нажмите «Обновить», чтобы загрузить расписание'),
      );
    }
    return _buildTable();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(_error!.message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Таблица ───

  /// Подстраивает высоты строк под новую ширину колонки.
  ///
  /// Ширина известна только на этапе раскладки, поэтому пересчёт делаем
  /// после кадра — иначе setState во время build.
  void _syncColumnWidth(double width) {
    if ((width - _layoutColumnWidth).abs() < 0.5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((width - _layoutColumnWidth).abs() < 0.5) return;
      setState(() {
        _layoutColumnWidth = width;
        _rebuildGeometry();
      });
    });
  }

  Widget _buildTable() {
    final leftWidth = _dayColWidth + _timeColWidth;
    final scheme = Theme.of(context).colorScheme;
    final border = Border.all(color: Theme.of(context).dividerColor);

    // Полоски прокрутки не рисуем, но жест и колесо работают как раньше.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyHeight = math.max(
            0.0,
            constraints.maxHeight - _headerHeight,
          );

          // Одна группа растягивается на всю ширину: горизонтальной
          // прокрутки тогда нет.
          final groups = _visibleGroupCols;
          final availableWidth = math.max(
            0.0,
            constraints.maxWidth - leftWidth,
          );
          // Растягиваем только когда ширина уже известна.
          final singleGroup = groups.length == 1 && availableWidth > 1;
          final tableWidth = singleGroup ? availableWidth : _totalWidth;
          final columnWidth = math.max(
            singleGroup
                ? availableWidth / (groups.first.hasSubgroups ? 2 : 1)
                : _groupColWidth,
            40.0,
          );
          // Ширина зависит от экрана — пересчитываем высоты строк,
          // когда она меняется (поворот, другая группа).
          _syncColumnWidth(columnWidth);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая колонка: дни и время. Едет синхронно со строками.
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    Container(
                      height: _headerHeight,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        border: border,
                      ),
                    ),
                    SizedBox(
                      height: bodyHeight,
                      child: ListView.builder(
                        controller: _daysVertical,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _dayBlocks.length,
                        itemBuilder: (context, index) =>
                            _buildDayBlock(_dayBlocks[index]),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _bodyHorizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        SizedBox(
                          height: _headerHeight,
                          child: _buildHeaderRow(columnWidth),
                        ),
                        SizedBox(
                          height: bodyHeight,
                          child: ListView.builder(
                            controller: _rowsVertical,
                            itemCount: _rows.length,
                            itemBuilder: (context, index) =>
                                _buildRow(index, columnWidth),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow(double columnWidth) {
    final children = <Widget>[];
    for (final group in _visibleGroupCols) {
      final width = group.hasSubgroups ? columnWidth * 2 : columnWidth;
      children.add(_headerCell(group.name, width));
    }
    return Row(children: children);
  }

  Widget _buildRow(int index, double columnWidth) {
    final row = _rows[index];
    final cells = <Widget>[];

    for (final group in _visibleGroupCols) {
      final cell = row.groupMap[group.name];
      if (group.hasSubgroups) {
        final sub1 = cell?.sub1Num ?? '';
        final sub1Den = cell?.sub1Den ?? '';
        final sub2 = cell?.sub2Num ?? '';
        final sub2Den = cell?.sub2Den ?? '';

        final samePair =
            sub1.trim() == sub2.trim() &&
            sub1Den.trim() == sub2Den.trim() &&
            (sub1.isNotEmpty || sub1Den.isNotEmpty);

        if (samePair) {
          cells.add(
            _twoLineCell(top: sub1, bottom: sub1Den, width: columnWidth * 2),
          );
        } else {
          cells.add(
            _twoLineCell(top: sub1, bottom: sub1Den, width: columnWidth),
          );
          cells.add(
            _twoLineCell(top: sub2, bottom: sub2Den, width: columnWidth),
          );
        }
      } else {
        cells.add(
          _twoLineCell(
            top: cell?.numerator ?? '',
            bottom: cell?.denominator ?? '',
            width: columnWidth,
          ),
        );
      }
    }

    return SizedBox(
      height: _rowHeights[index],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cells,
      ),
    );
  }

  Widget _buildDayBlock(_DayBlock block) {
    final timeCells = <Widget>[];
    for (var i = 0; i < block.rowCount; i++) {
      timeCells.add(
        SizedBox(
          height: _rowHeights[block.startIndex + i],
          child: _timeCell(_rows[block.startIndex + i].time),
        ),
      );
    }

    return SizedBox(
      height: block.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _dayColWidth,
            height: block.height,
            child: _verticalDayCell(block.day),
          ),
          Column(children: timeCells),
        ],
      ),
    );
  }

  Widget _verticalDayCell(String text) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      alignment: Alignment.center,
      child: text.isEmpty
          ? const SizedBox.shrink()
          : RotatedBox(
              quarterTurns: 3,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }

  Widget _headerCell(String text, double width) {
    return Container(
      width: width,
      height: _headerHeight,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _timeCell(String text) {
    final parts = text.split(RegExp(r'[-–—]'));
    final displayText = parts.length == 2
        ? '${parts[0].trim()}\n- ${parts[1].trim()}'
        : text;

    return Container(
      width: _timeColWidth,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, height: 1.2),
      ),
    );
  }

  Widget _twoLineCell({
    required String top,
    required String bottom,
    required double width,
  }) {
    final border = Border.all(color: Theme.of(context).dividerColor);

    if (top.trim().isEmpty && bottom.trim().isEmpty) {
      return Container(
        width: width,
        decoration: BoxDecoration(border: border),
      );
    }

    final same = top.trim().isNotEmpty && top.trim() == bottom.trim();

    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(border: border),
      child: same
          ? Center(
              child: Text(
                top,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      top,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      bottom,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatDt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _RowSpec {
  final String day;
  final String time;
  final Map<String, LessonCell> groupMap;
  _RowSpec({required this.day, required this.time, required this.groupMap});
}

/// Блок строк одного дня: подпись дня слева на всю высоту блока.
class _DayBlock {
  final String day;
  final int startIndex;
  final int rowCount;
  final double height;
  const _DayBlock({
    required this.day,
    required this.startIndex,
    required this.rowCount,
    required this.height,
  });
}
