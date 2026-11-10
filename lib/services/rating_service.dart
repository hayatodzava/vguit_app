import 'package:shared_preferences/shared_preferences.dart';

import '../models/rating.dart';
import 'cache/cache_store.dart';
import 'net.dart';
import 'rating_parser.dart';
import 'rating_session.dart';

/// Данные с меткой времени последнего обновления.
class CachedData<T> {
  final T data;
  final DateTime updatedAt;
  const CachedData({required this.data, required this.updatedAt});
}

class RatingService {
  RatingService();

  final RatingSession _session = RatingSession();

  static const CacheStore _store = CacheStore(CacheSection.rating);

  static const String _defaultUrl =
      'https://rating.vsuet.ru/web/ved/Default.aspx';
  static const String _vedBaseUrl = 'https://rating.vsuet.ru/web/Ved/Ved.aspx';

  static const String _ckFaculties = 'faculties';
  static const String _ckGroups = 'groups_';
  static const String _ckSubjects = 'subjects_';
  static const String _ckVedomost = 'ved_';

  String _facultyId = '';
  String _groupId = '';

  // ───── Публичные геттеры состояния ─────

  String get facultyId => _facultyId;
  String get groupId => _groupId;

  /// Учебный год и семестр берутся из самой страницы, а не из констант:
  /// сайт сам подставляет актуальные значения, и жёстко зашитый год
  /// однажды превратился бы в 500 при смене учебного года.
  String get year => _session.fieldValue('cmbYears') ?? '';
  String get sem => _session.fieldValue('cmbSem') ?? '';

  bool get hasSession => _session.hasFormState;

  // ───── Инициализация сессии ─────

  Future<List<Faculty>> init() async {
    final html = await _session.get(
      _defaultUrl,
      action: 'Загрузка списка факультетов',
    );
    final faculties = RatingParser.parseFaculties(html);
    if (faculties.isEmpty) {
      throw AppException.parse(
        'Страница рейтинга открылась, но список факультетов на ней не найден — '
        'возможно, изменился сайт.',
      );
    }
    return faculties;
  }

  Future<({List<Group> groups, List<Subject> subjects})> selectFaculty(
    String facultyId,
  ) async {
    await _ensureSession();
    if (!_session.hasOption('cmbFacultets', facultyId)) {
      throw AppException(
        'Этого факультета больше нет в списке на сайте рейтинга. '
        'Выберите факультет заново.',
        kind: AppErrorKind.parse,
      );
    }
    _facultyId = facultyId;

    final html = await _postWithRetry(
      _facultyOverrides(facultyId),
      action: 'Загрузка групп факультета',
    );

    final groups = RatingParser.parseGroups(html);
    if (groups.isNotEmpty) _groupId = groups.first.id;
    return (groups: groups, subjects: RatingParser.parseSubjects(html));
  }

  /// Postback выбора факультета.
  ///
  /// Группу обязательно отправляем пустой: сайт при смене факультета
  /// пытается восстановить прежнюю группу и падает с 500, если её нет
  /// в списке нового факультета.
  Map<String, String> _facultyOverrides(String facultyId) {
    final control = _target('cmbFacultets');
    final overrides = <String, String>{
      '__EVENTTARGET': control,
      control: facultyId,
    };
    final groupControl = _session.fieldName('cmbGroups');
    if (groupControl != null) overrides[groupControl] = '';
    return overrides;
  }

  Future<List<Subject>> selectGroup(String groupId) async {
    await _ensureSession();
    if (!_session.hasOption('cmbGroups', groupId)) {
      throw AppException(
        'Выбранной группы больше нет на сайте рейтинга. '
        'Выберите группу заново.',
        kind: AppErrorKind.parse,
      );
    }

    // Группа уже выбрана на странице: postback не вызовет SelectedIndexChanged,
    // и таблица предметов останется пустой. Берём её из последней страницы.
    if (_session.fieldValue('cmbGroups') == groupId) {
      final page = _session.lastPage;
      if (page != null) {
        _groupId = groupId;
        return RatingParser.parseSubjects(page);
      }
    }

    _groupId = groupId;
    final control = _target('cmbGroups');
    final html = await _postWithRetry(<String, String>{
      '__EVENTTARGET': control,
      control: groupId,
    }, action: 'Загрузка предметов группы');
    return RatingParser.parseSubjects(html);
  }

  Future<Vedomost> fetchVedomost(String subjectId) async {
    await _ensureSession();
    final html = await _session.get(
      '$_vedBaseUrl?id=$subjectId',
      action: 'Загрузка ведомости',
    );
    final vedomost = RatingParser.parseVedomost(html, subjectId);
    if (vedomost.students.isEmpty) {
      throw AppException.parse(
        'Ведомость загрузилась, но список студентов в ней не найден.',
      );
    }
    return vedomost;
  }

  /// Имя контрола в форме; если префикс на сайте изменится — берём из формы.
  String _target(String suffix) =>
      _session.fieldName(suffix) ?? 'ctl00\$ContentPage\$$suffix';

  /// Postback с одной повторной попыткой.
  ///
  /// 500 от ASP.NET почти всегда означает устаревшее состояние формы
  /// (сессия на сайте истекла). Тогда перечитываем страницу, восстанавливаем
  /// выбор факультета и повторяем — пользователю не нужно жать «обновить».
  Future<String> _postWithRetry(
    Map<String, String> overrides, {
    required String action,
  }) async {
    try {
      return await _session.post(_defaultUrl, overrides, action: action);
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.server) rethrow;
      await _recoverSession();
      return _session.post(_defaultUrl, overrides, action: action);
    }
  }

  /// Возвращает сессию в состояние «страница открыта, факультет выбран».
  Future<void> _recoverSession() async {
    await init();
    final faculty = _facultyId;
    if (faculty.isEmpty) return;
    if (!_session.hasOption('cmbFacultets', faculty)) return;
    await _session.post(
      _defaultUrl,
      _facultyOverrides(faculty),
      action: 'Восстановление сессии',
    );
  }

  /// ASP.NET-сессия должна быть «тёплой»: без cookies и __VIEWSTATE
  /// postback-запросы и страница ведомости могут не открыться.
  Future<void> _ensureSession() async {
    if (_session.hasFormState) return;
    await init();
  }

  // ═══════════════════════════════════════════════════════════
  //   КЭШ — раздел «Рейтинг»
  // ═══════════════════════════════════════════════════════════

  Future<void> _saveJson(String key, Object data) async {
    await _store.writeJson(key, data);
    await _store.writeTimestamp(key, DateTime.now());
  }

  Future<DateTime?> _getUpdatedAt(String key) => _store.readTimestamp(key);

  Future<Object?> _loadJson(String key) => _store.readJson(key);

  // ───── Факультеты ─────

  Future<CachedData<List<Faculty>>?> loadFacultiesFromCache() async {
    final raw = await _loadJson(_ckFaculties);
    if (raw is! List) return null;
    final at = await _getUpdatedAt(_ckFaculties);
    try {
      return CachedData(
        data: raw
            .map(
              (e) => Faculty(
                id: (e as Map)['id'] as String,
                name: e['name'] as String,
              ),
            )
            .toList(),
        updatedAt: at ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFacultiesToCache(List<Faculty> list) async {
    await _saveJson(
      _ckFaculties,
      list.map((f) => {'id': f.id, 'name': f.name}).toList(),
    );
  }

  // ───── Группы ─────

  Future<CachedData<List<Group>>?> loadGroupsFromCache(String facultyId) async {
    final key = '$_ckGroups$facultyId';
    final raw = await _loadJson(key);
    if (raw is! List) return null;
    final at = await _getUpdatedAt(key);
    try {
      return CachedData(
        data: raw
            .map(
              (e) => Group(
                id: (e as Map)['id'] as String,
                name: e['name'] as String,
              ),
            )
            .toList(),
        updatedAt: at ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGroupsToCache(String facultyId, List<Group> list) async {
    await _saveJson(
      '$_ckGroups$facultyId',
      list.map((g) => {'id': g.id, 'name': g.name}).toList(),
    );
  }

  // ───── Предметы ─────

  Future<CachedData<List<Subject>>?> loadSubjectsFromCache(
    String groupId,
  ) async {
    final key = '$_ckSubjects$groupId';
    final raw = await _loadJson(key);
    if (raw is! List) return null;
    final at = await _getUpdatedAt(key);
    try {
      return CachedData(
        data: raw
            .map(
              (e) => Subject(
                id: (e as Map)['id'] as String,
                name: e['name'] as String,
                type: e['type'] as String,
                closed: e['closed'] as bool,
              ),
            )
            .toList(),
        updatedAt: at ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSubjectsToCache(String groupId, List<Subject> list) async {
    await _saveJson(
      '$_ckSubjects$groupId',
      list
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'type': s.type,
              'closed': s.closed,
            },
          )
          .toList(),
    );
  }

  // ───── Ведомости ─────

  Future<CachedData<Vedomost>?> loadVedomostFromCache(String subjectId) async {
    final key = '$_ckVedomost$subjectId';
    final raw = await _loadJson(key);
    if (raw is! Map) return null;
    final at = await _getUpdatedAt(key);
    try {
      return CachedData(
        data: _vedomostFromJson(raw),
        updatedAt: at ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveVedomostToCache(Vedomost v) async {
    await _saveJson('$_ckVedomost${v.subjectId}', _vedomostToJson(v));
  }

  // ───── Сериализация Vedomost ─────

  Map<String, dynamic> _vedomostToJson(Vedomost v) => {
    'subjectId': v.subjectId,
    'subjectName': v.subjectName,
    'groupName': v.groupName,
    'teacher': v.teacher,
    'semester': v.semester,
    'type': v.type,
    'year': v.year,
    'controlPoints': v.controlPoints
        .map(
          (cp) => {
            'name': cp.name,
            'date': cp.date,
            'weightPercent': cp.weightPercent,
            'weights': cp.weights,
          },
        )
        .toList(),
    'students': v.students
        .map(
          (s) => {
            'number': s.number,
            'recordBook': s.recordBook,
            'scores': s.scores,
            'ktTotals': s.ktTotals,
            'finalRating': s.finalRating,
            'grade': s.grade,
          },
        )
        .toList(),
  };

  Vedomost _vedomostFromJson(Map json) => Vedomost(
    subjectId: json['subjectId'] as String,
    subjectName: json['subjectName'] as String,
    groupName: json['groupName'] as String,
    teacher: json['teacher'] as String,
    semester: json['semester'] as String,
    type: json['type'] as String,
    year: json['year'] as String,
    controlPoints: (json['controlPoints'] as List)
        .map(
          (e) => ControlPoint(
            name: e['name'] as String,
            date: e['date'] as String,
            weightPercent: (e['weightPercent'] as num).toInt(),
            weights: (e['weights'] as List)
                .map((w) => (w as num).toInt())
                .toList(),
          ),
        )
        .toList(),
    students: (json['students'] as List)
        .map(
          (e) => StudentRow(
            number: (e['number'] as num).toInt(),
            recordBook: e['recordBook'] as String,
            scores: (e['scores'] as List).cast<String>(),
            ktTotals: (e['ktTotals'] as List).cast<String>(),
            finalRating: e['finalRating'] as String,
            grade: e['grade'] as String,
          ),
        )
        .toList(),
  );

  // ───── Сохранение последнего выбора ─────
  //
  // Выбор пользователя живёт в своей группе ключей и НЕ попадает
  // под очистку кэша.

  static const String _selFaculty = 'sel_faculty';
  static const String _selGroup = 'sel_group';
  static const String _selRecordBook = 'sel_recordbook';

  static const String _legacySelFaculty = 'rating_sel_faculty';
  static const String _legacySelGroup = 'rating_sel_group';
  static const String _legacySelRecordBook = 'rating_sel_recordbook';

  Future<String?> _readSelection(String key, String legacyKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? prefs.getString(legacyKey);
  }

  Future<void> saveSelectedFacultyId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selFaculty, id);
  }

  Future<String?> loadSelectedFacultyId() =>
      _readSelection(_selFaculty, _legacySelFaculty);

  Future<void> saveSelectedGroupId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selGroup, id);
  }

  Future<String?> loadSelectedGroupId() =>
      _readSelection(_selGroup, _legacySelGroup);

  Future<void> clearSelectedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selGroup);
    await prefs.remove(_legacySelGroup);
  }

  Future<void> saveSelectedRecordBook(String rb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selRecordBook, rb);
  }

  Future<String?> loadSelectedRecordBook() =>
      _readSelection(_selRecordBook, _legacySelRecordBook);
}
