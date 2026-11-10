import 'package:flutter/material.dart';

import '../models/rating.dart';
import '../services/net.dart';
import '../services/rating_service.dart';
import '../widgets/error_banner.dart';
import '../widgets/error_dialog.dart';
import 'rating_my_scores_screen.dart';
import 'rating_vedomost_screen.dart';
import 'search_picker_dialog.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final RatingService _service = RatingService();

  List<Faculty> _faculties = const <Faculty>[];
  List<Group> _groups = const <Group>[];
  List<Subject> _subjects = const <Subject>[];

  Faculty? _selectedFaculty;
  Group? _selectedGroup;

  bool _loadingFaculties = false;
  bool _loadingGroups = false;
  bool _loadingSubjects = false;

  AppException? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  bool get _anyLoading =>
      _loadingFaculties || _loadingGroups || _loadingSubjects;

  Future<void> _bootstrap() async {
    setState(() {
      _loadingFaculties = true;
      _error = null;
    });

    // 1. Факультеты: сначала кэш, потом сеть.
    if (!await _loadFaculties()) {
      if (mounted) setState(() => _loadingFaculties = false);
      return;
    }

    // 2. Восстанавливаем факультет.
    try {
      final savedFacultyId = await _service.loadSelectedFacultyId();
      if (savedFacultyId != null) {
        for (final faculty in _faculties) {
          if (faculty.id == savedFacultyId) _selectedFaculty = faculty;
        }
      }
    } catch (error) {
      _handleError(
        error,
        'Не удалось восстановить факультет',
        showDialog: false,
      );
    }

    // 3. Группы и предметы. Каждый шаг отдельно: если сети нет, но кэш
    //    есть, покажем то, что сохранено, вместо пустого экрана.
    final faculty = _selectedFaculty;
    if (faculty != null) {
      try {
        await _loadGroups(faculty);
      } catch (error) {
        _handleError(error, 'Не удалось загрузить группы', showDialog: false);
      }
      try {
        await _restoreGroup();
      } catch (error) {
        _handleError(error, 'Не удалось загрузить предметы', showDialog: false);
      }
    }

    if (mounted) setState(() => _loadingFaculties = false);
  }

  /// Факультеты из кэша или с сайта. false — показать нечего.
  Future<bool> _loadFaculties({bool force = false}) async {
    if (!force) {
      final cached = await _service.loadFacultiesFromCache();
      if (cached != null && cached.data.isNotEmpty) {
        _faculties = cached.data;
        _lastUpdated = cached.updatedAt;
        return true;
      }
    }
    try {
      _faculties = await _service.init();
      await _service.saveFacultiesToCache(_faculties);
      _lastUpdated = DateTime.now();
      return true;
    } catch (error) {
      _handleError(error, 'Не удалось загрузить факультеты');
      return false;
    }
  }

  Future<void> _restoreGroup() async {
    final savedGroupId = await _service.loadSelectedGroupId();
    if (savedGroupId == null) return;
    for (final group in _groups) {
      if (group.id != savedGroupId) continue;
      _selectedGroup = group;
      await _loadSubjects(group);
      return;
    }
  }

  Future<void> _loadGroups(Faculty faculty, {bool force = false}) async {
    if (!force) {
      final cached = await _service.loadGroupsFromCache(faculty.id);
      if (cached != null && cached.data.isNotEmpty) {
        _groups = cached.data;
        _lastUpdated = cached.updatedAt;
        return;
      }
    }
    final result = await _service.selectFaculty(faculty.id);
    _groups = result.groups;
    await _service.saveGroupsToCache(faculty.id, _groups);
  }

  Future<void> _loadSubjects(Group group, {bool force = false}) async {
    if (!force) {
      final cached = await _service.loadSubjectsFromCache(group.id);
      if (cached != null && cached.data.isNotEmpty) {
        _subjects = cached.data;
        _lastUpdated = cached.updatedAt;
        return;
      }
    }
    _subjects = await _service.selectGroup(group.id);
    await _service.saveSubjectsToCache(group.id, _subjects);
  }

  // ─── Действия пользователя ───

  /// Обновление с сервера.
  ///
  /// Кэш заранее не чистим: каждый раздел перезаписывается только после
  /// успешного ответа сайта. Если сети нет, экран остаётся с тем, что
  /// уже сохранено, а не с пустотой.
  Future<void> _refreshAll() async {
    setState(() {
      _loadingFaculties = true;
      _error = null;
    });
    try {
      // 1. Факультеты — обязательно с сервера.
      if (!await _loadFaculties(force: true)) return;
      if (!mounted) return;

      final facultyId = _selectedFaculty?.id;
      if (facultyId != null) {
        Faculty? match;
        for (final faculty in _faculties) {
          if (faculty.id == facultyId) match = faculty;
        }
        if (match == null) {
          // Факультет исчез из списка — сбрасываем выбор, иначе выпадающий
          // список упадёт на значении, которого нет среди пунктов.
          setState(() {
            _selectedFaculty = null;
            _selectedGroup = null;
            _groups = const <Group>[];
            _subjects = const <Subject>[];
          });
        } else {
          setState(() => _selectedFaculty = match);
        }
      }

      // 2. Группы выбранного факультета.
      final faculty = _selectedFaculty;
      if (faculty == null) return;
      setState(() => _loadingGroups = true);
      await _loadGroups(faculty, force: true);
      if (!mounted) return;
      setState(() {});

      // 3. Предметы выбранной группы.
      final selected = _selectedGroup;
      if (selected != null) {
        // Группа могла исчезнуть из списка (новый учебный год) —
        // тогда сбрасываем выбор вместо запроса, который вернёт ошибку.
        if (_groups.any((group) => group.id == selected.id)) {
          await _loadSubjects(selected, force: true);
        } else {
          await _service.clearSelectedGroup();
          if (mounted) setState(() => _selectedGroup = null);
        }
      }
      if (mounted) setState(() => _lastUpdated = DateTime.now());
    } catch (error) {
      _handleError(error, 'Не удалось обновить рейтинг');
    } finally {
      if (mounted) {
        setState(() {
          _loadingFaculties = false;
          _loadingGroups = false;
        });
      }
    }
  }

  Future<void> _selectFaculty(Faculty? faculty) async {
    if (faculty == null) return;
    setState(() {
      _selectedFaculty = faculty;
      _selectedGroup = null;
      _groups = const <Group>[];
      _subjects = const <Subject>[];
      _error = null;
      _loadingGroups = true;
    });
    try {
      await _service.saveSelectedFacultyId(faculty.id);
      await _service.clearSelectedGroup();
      await _loadGroups(faculty);
    } catch (error) {
      _handleError(error, 'Не удалось загрузить группы');
    } finally {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _selectGroup(Group group) async {
    setState(() {
      _selectedGroup = group;
      _subjects = const <Subject>[];
      _error = null;
      _loadingSubjects = true;
    });
    try {
      await _service.saveSelectedGroupId(group.id);
      await _loadSubjects(group);
    } catch (error) {
      _handleError(error, 'Не удалось загрузить предметы');
    } finally {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  void _openVedomost(Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RatingVedomostScreen(service: _service, subject: subject),
      ),
    );
  }

  Future<void> _openMyScores() async {
    if (_selectedGroup == null || _subjects.isEmpty) return;

    setState(() => _loadingSubjects = true);
    List<String> recordBooks = const <String>[];
    try {
      final first = await _loadOrFetchVedomost(_subjects.first.id);
      recordBooks = first.students
          .map((student) => student.recordBook)
          .where((book) => book.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      if (mounted) {
        _handleError(error, 'Не удалось получить список зачёток');
        setState(() => _loadingSubjects = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingSubjects = false);

    final chosen = await showSearchPickerDialog<String>(
      context: context,
      title: 'Выберите номер зачётки',
      items: recordBooks,
      hint: 'Введите номер зачётки',
    );
    if (!mounted || chosen == null) return;

    await _service.saveSelectedRecordBook(chosen);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RatingMyScoresScreen(
          service: _service,
          subjects: _subjects,
          recordBook: chosen,
          groupName: _selectedGroup!.name,
        ),
      ),
    );
  }

  Future<Vedomost> _loadOrFetchVedomost(String subjectId) async {
    final cached = await _service.loadVedomostFromCache(subjectId);
    if (cached != null) return cached.data;
    final fresh = await _service.fetchVedomost(subjectId);
    await _service.saveVedomostToCache(fresh);
    return fresh;
  }

  /// Показывает ошибку плашкой и, если нужно, диалогом.
  ///
  /// Для второстепенных шагов (группы, предметы) хватает плашки: экран
  /// уже что-то показывает из кэша, и закрывать его диалогом не надо.
  void _handleError(Object error, String title, {bool showDialog = true}) {
    final exception = AppException.from(error);
    if (!mounted) return;
    setState(() => _error = exception);
    if (showDialog) {
      showErrorDialog(context, title: title, error: exception);
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рейтинг'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить с сервера',
            onPressed: _anyLoading ? null : _refreshAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_error != null) ErrorBanner(error: _error!, onRetry: _refreshAll),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<Faculty>(
            initialValue: _selectedFaculty,
            key: ValueKey('faculty-${_selectedFaculty?.id ?? 'none'}'),
            decoration: const InputDecoration(
              labelText: 'Факультет',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _faculties
                .map(
                  (f) =>
                      DropdownMenuItem<Faculty>(value: f, child: Text(f.name)),
                )
                .toList(),
            onChanged: _anyLoading ? null : _selectFaculty,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.group),
            label: Text(
              _selectedGroup?.name ?? 'Выбрать группу',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _groups.isEmpty || _anyLoading
                ? null
                : () async {
                    final chosen = await showSearchPickerDialog<Group>(
                      context: context,
                      title: 'Выберите группу',
                      items: _groups,
                      hint: 'Поиск группы',
                      labelBuilder: (group) => group.name,
                    );
                    if (chosen != null) await _selectGroup(chosen);
                  },
          ),
          const SizedBox(height: 8),
          if (_subjects.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Найти мою зачётку'),
              onPressed: _anyLoading ? null : _openMyScores,
            ),
          const SizedBox(height: 6),
          if (_lastUpdated != null)
            Text(
              'Обновлено: ${_formatDt(_lastUpdated!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_anyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedFaculty == null) {
      return const Center(
        child: Text('Выберите факультет', style: TextStyle(fontSize: 16)),
      );
    }
    if (_selectedGroup == null) {
      return const Center(
        child: Text('Выберите группу', style: TextStyle(fontSize: 16)),
      );
    }
    if (_subjects.isEmpty) {
      return const Center(
        child: Text('У группы нет предметов', style: TextStyle(fontSize: 16)),
      );
    }
    return ListView.builder(
      itemCount: _subjects.length,
      itemBuilder: (context, index) {
        final subject = _subjects[index];
        return ListTile(
          leading: Icon(
            subject.type.toLowerCase().contains('экзамен')
                ? Icons.assignment
                : Icons.check_circle_outline,
          ),
          title: Text(subject.name),
          subtitle: Text(subject.type),
          trailing: subject.closed
              ? const Icon(Icons.lock, size: 18)
              : const Icon(Icons.lock_open, size: 18),
          onTap: () => _openVedomost(subject),
        );
      },
    );
  }

  String _formatDt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
