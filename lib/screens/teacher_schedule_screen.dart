import 'package:flutter/material.dart';

import '../models/teacher_schedule.dart';
import '../services/net.dart';
import '../services/teacher_service.dart';
import '../widgets/error_banner.dart';
import '../widgets/error_dialog.dart';
import 'search_picker_dialog.dart';

import 'package:sticky_headers/sticky_headers.dart';

class TeacherScheduleScreen extends StatefulWidget {
  const TeacherScheduleScreen({super.key});

  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
  static const List<String> _daysOrder = [
    'ПОНЕДЕЛЬНИК',
    'ВТОРНИК',
    'СРЕДА',
    'ЧЕТВЕРГ',
    'ПЯТНИЦА',
    'СУББОТА',
    'ВОСКРЕСЕНЬЕ',
  ];

  static const String _allDays = '__all__';

  final TeacherService _service = const TeacherService();

  List<String> _teachers = const <String>[];
  String? _selectedTeacher;
  String? _selectedDay;
  List<TeacherLesson> _lessons = const <TeacherLesson>[];
  bool _loadingTeachers = false;
  bool _loadingSchedule = false;
  AppException? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _initTeachers();
  }

  Future<void> _initTeachers() async {
    setState(() {
      _loadingTeachers = true;
      _error = null;
    });
    try {
      final cached = await _service.loadTeachersFromCache();
      if (cached != null && cached.isNotEmpty) {
        if (!mounted) return;
        setState(() => _teachers = cached);
        return;
      }
      await _refreshTeachers();
    } catch (error) {
      _handleError(error, 'Не удалось загрузить список преподавателей');
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<bool> _refreshTeachers() async {
    setState(() {
      _loadingTeachers = true;
      _error = null;
    });
    try {
      final list = await _service.fetchTeachers();
      await _service.saveTeachersToCache(list);
      if (!mounted) return true;
      setState(() => _teachers = list);
      return true;
    } catch (error) {
      _handleError(error, 'Не удалось загрузить список преподавателей');
      return false;
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _selectTeacher(String? name) async {
    if (name == null) return;
    setState(() {
      _selectedTeacher = name;
      _selectedDay = null;
      _lessons = const <TeacherLesson>[];
      _error = null;
    });
    try {
      final cached = await _service.loadScheduleFromCache(name);
      if (cached != null && cached.isNotEmpty) {
        final at = await _service.loadUpdatedAt(name);
        if (!mounted) return;
        setState(() {
          _lessons = cached;
          _lastUpdated = at;
        });
        return;
      }
      await _refreshSchedule();
    } catch (error) {
      _handleError(error, 'Не удалось загрузить расписание преподавателя');
    }
  }

  Future<void> _refreshSchedule() async {
    final teacher = _selectedTeacher;
    if (teacher == null) return;
    setState(() {
      _loadingSchedule = true;
      _error = null;
    });
    try {
      final list = await _service.fetchSchedule(teacher);
      await _service.saveScheduleToCache(teacher, list);
      if (!mounted) return;
      setState(() {
        _lessons = list;
        _lastUpdated = DateTime.now();
      });
    } catch (error) {
      _handleError(error, 'Не удалось загрузить расписание преподавателя');
    } finally {
      if (mounted) setState(() => _loadingSchedule = false);
    }
  }

  /// Обновление с сервера.
  ///
  /// Кэш заранее не чистим: свежие данные записываются только после
  /// успешного скачивания. Если сети нет, остаётся то, что уже сохранено,
  /// и расписание можно смотреть офлайн.
  Future<void> _refreshAll() async {
    final teachersLoaded = await _refreshTeachers();
    if (!teachersLoaded || !mounted) return;
    if (_selectedTeacher != null) {
      await _refreshSchedule();
    }
  }

  void _handleError(Object error, String title) {
    final exception = AppException.from(error);
    if (!mounted) return;
    setState(() => _error = exception);
    showErrorDialog(context, title: title, error: exception);
  }

  List<TeacherLesson> get _filteredLessons {
    final day = _selectedDay;
    if (day == null) return _lessons;
    return _lessons
        .where((lesson) => lesson.day.toUpperCase() == day)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person),
                      label: Text(
                        _selectedTeacher ?? 'Выбрать преподавателя',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _teachers.isEmpty
                          ? null
                          : () async {
                              final chosen =
                                  await showSearchPickerDialog<String>(
                                    context: context,
                                    title: 'Преподаватель',
                                    items: _teachers,
                                    hint: 'Поиск по ФИО',
                                  );
                              if (chosen != null) await _selectTeacher(chosen);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Обновить',
                    onPressed: _loadingTeachers || _loadingSchedule
                        ? null
                        : _refreshAll,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedDay ?? _allDays,
                key: ValueKey('day-${_selectedDay ?? _allDays}'),
                decoration: const InputDecoration(
                  labelText: 'День недели',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: _allDays,
                    child: Text('Все дни'),
                  ),
                  ..._daysOrder.map(
                    (day) => DropdownMenuItem<String>(
                      value: day,
                      child: Text(_capitalizeDay(day)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _selectedDay = value == _allDays ? null : value,
                ),
              ),
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Обновлено: ${_formatDt(_lastUpdated!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null)
          ErrorBanner(
            error: _error!,
            onRetry: _selectedTeacher == null
                ? _refreshTeachers
                : _refreshSchedule,
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loadingSchedule || (_loadingTeachers && _teachers.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_teachers.isEmpty) {
      return _buildEmpty('Не удалось получить список преподавателей');
    }
    if (_selectedTeacher == null) {
      return _buildEmpty('Выберите преподавателя');
    }
    if (_lessons.isEmpty) {
      return _buildEmpty('В расписании преподавателя нет пар');
    }
    final filtered = _filteredLessons;
    if (filtered.isEmpty) {
      return _buildEmpty('Нет пар в этот день');
    }

    final Map<String, List<TeacherSlot>> byDay = {};
    for (final slot in groupIntoSlots(filtered)) {
      final day = slot.day.toUpperCase().trim();
      byDay.putIfAbsent(day, () => <TeacherSlot>[]).add(slot);
    }
    final orderedDays = _daysOrder.where(byDay.containsKey).toList();

    return ListView.builder(
      itemCount: orderedDays.length,
      itemBuilder: (context, index) {
        final day = orderedDays[index];
        final slots = byDay[day]!;

        return StickyHeader(
          header: Container(
            height: 40,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              _capitalizeDay(day),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          content: Column(children: slots.map(_buildSlotCard).toList()),
        );
      },
    );
  }

  Widget _buildEmpty(String text) {
    return Center(child: Text(text));
  }

  /// Карточка на один слот «день + время».
  ///
  /// Обычная пара — одна карточка. Если в это же время идёт другая пара
  /// (числитель и знаменатель с разными предметами), карточки остаются
  /// раздельными, но связываются общей рамкой со временем сверху —
  /// видно, что это одно окно расписания.
  Widget _buildSlotCard(TeacherSlot slot) {
    if (!slot.hasSeveral) {
      return _buildLessonCard(slot.lessons.single, showTime: true);
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 0, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            width: 3,
            color: scheme.primary.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 2),
            child: Text(
              slot.time,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final lesson in slot.lessons)
            _buildLessonCard(lesson, showTime: false),
        ],
      ),
    );
  }

  Widget _buildLessonCard(TeacherLesson lesson, {required bool showTime}) {
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: showTime ? 12 : 0,
        vertical: showTime ? 6 : 4,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTime) ...[
              SizedBox(
                width: 82,
                child: Text(
                  lesson.time,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: _buildLessonBody(lesson)),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonBody(TeacherLesson lesson) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lesson.week.isNotEmpty) ...[
          _buildWeekLabel(lesson.week),
          const SizedBox(height: 6),
        ],
        Text(
          lesson.subject,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (lesson.type.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(lesson.type, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 4),
        if (lesson.room.isNotEmpty)
          Text(
            'Аудитория: ${lesson.room}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (lesson.groups.isNotEmpty)
          Text(
            'Группы: ${lesson.groups.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  /// Неделя пары: «числитель», «знаменатель» или «числитель и знаменатель».
  Widget _buildWeekLabel(String week) {
    final both = week == TeacherLesson.weekBoth;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: both
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        week,
        style: TextStyle(
          fontSize: 10,
          height: 1.25,
          color: both ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _capitalizeDay(String day) {
    final lower = day.toLowerCase().trim();
    if (lower.isEmpty) return day;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _formatDt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}
