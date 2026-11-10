# Код-ревью `vguit_app` — что улучшить

Мобильное приложение ВГУИТ (Flutter, 24 файла / ~4,5 тыс. строк в `lib/`):
расписание из xlsx, рейтинг-ведомости с сайта `rating.vsuet.ru`,
расписание преподавателей с `timetable.vsuet.ru`, карта корпусов с A*-маршрутом.

Дата ревью: 2026-11-07. Flutter 3.47.6 / Dart 3.13.5 (SDK в `E:\sdk\flutter`).

> **Статус после второй итерации (2026-11-07).** Блок «карта и маршрут»
> переписан: исправлены данные карт, веса рёбер, A*, преобразование координат,
> отрисовка. Проверка: `dart run tool/map_check.dart` — 330 маршрутов,
> 0 расхождений с эталонным Дейкстрой, все аудитории достижимы.
> Актуальный трекер задач — `PROBLEMS.txt`; разделы 3.1–3.7 ниже описывают
> состояние **до** правок и оставлены как история решений.

---

## 0. Что и как проверялось

* Прочитаны все 24 файла `lib/`, `pubspec.yaml`, `analysis_options.yaml`,
  `test/`, `android/app/build.gradle.kts`, `AndroidManifest.xml`,
  все 6 JSON-карт из `assets/map/` (разбор скриптом: узлы, рёбра, метаданные лестниц).
* `flutter analyze` в этой песочнице **запустить не удалось** (инструмент зависает на
  блокировке доступа к своему кэшу вне рабочей папки), поэтому замечания линтера
  ниже — результат ручного прохода (помечены как «вероятное предупреждение»).
* В проекте **нет git-репозитория** (`.git` отсутствует), поэтому истории изменений
  и blame нет. `build/` и `.dart_tool/` лежат рядом с исходниками.

---

## 1. Топ-10 по соотношению «эффект / трудозатраты»

| # | Что сделать | Файл | Эффект |
|---|---|---|---|
| 1 | Исправить данные карты: `floor_4.json` без номера этажа, у лестниц этажей 2–5 нет `stairsGroupId`/`connectsFloors` | `assets/map/*.json` | Маршрут между этажами 2–5 сейчас **невозможен** |
| 2 | Вес ребра = евклидово расстояние, а не его квадрат; поднять стоимость лестницы | `route_builder.dart:84`, `:24` | A* перестаёт выбирать «зигзаг» и «бесплатные» переходы |
| 3 | Заменить `SplayTreeSet` на нормальную кучу (ключ меняется внутри множества) | `route_builder.dart:48-74` | Корректный кратчайший путь вместо «как получится» |
| 4 | Учесть `fitScale` в `_screenToMap` / вынести `MapTransform` | `map_screen.dart:43-66` | Жест «зум под пальцем» работает, метки не уезжают на планшетах |
| 5 | Таймауты + типизированные ошибки во всех `http`-запросах | `rating_session.dart`, `teacher_service.dart`, `schedule_screen.dart` | Нет вечных спиннеров и «проглатывания» сбоев |
| 6 | `if (!mounted) return;` в асинхронных циклах | `rating_my_scores_screen.dart:83` | Убирает `setState() after dispose` |
| 7 | Перенести xlsx-кэш из SharedPreferences в файл | `schedule_cache.dart` | Нет ANR/пиков памяти при старте |
| 8 | Парсинг xlsx в изоляте + кэш разобранной модели | `schedule_screen.dart:135` | Нет фризов при смене курса/факультета |
| 9 | Полноценный декодер windows-1251 | `rating_session.dart:63-87` | `№`, `–`, `«»` не превращаются в `?` |
| 10 | Тесты на парсеры и A* (сейчас единственный тест падает) | `test/` | Регрессии в разборщиках HTML/xlsx ловятся локально |

---

## 2. Что в проекте сделано хорошо

Чтобы не выглядело как «всё плохо»:

* Внятное разделение `models / services / screens`; парсеры вынесены из виджетов.
* Офлайн-первый сценарий: кэш в `shared_preferences`, «сначала кэш — потом сеть».
* Маршрутизация — честный A* по графу этажей с межэтажными состояниями,
  а не хардкод «иди по коридору».
* `showSearchPickerDialog` — один переиспользуемый диалог с нормальной сортировкой
  по релевантности (точное → «начинается с» → «содержит»).
* Обработка объединённых ячеек в xlsx и подгрупп (`sub1/sub2`) — самая сложная часть
  парсера расписания, и она реализована.
* Тёмная/светлая тема через `ChangeNotifier`, без лишних зависимостей.

---

## 3. P0 — функциональные баги

### 3.1 `floor_4.json` не имеет номера этажа → этаж 4 исчез из приложения

`assets/map/floor_4.json`:

```json
{
  "floor": null,
  ...
}
```

`map_loader.dart:35`:

```dart
floor: (map['floor'] as num?)?.toInt() ?? 0,
```

`null` молча превращается в **0**. Следствия, видимые пользователю:

* в переключателе этажей (`map_screen.dart:418-456`) кнопки `-1, 0, 1, 2, 3, 5` —
  кнопки «4» нет, зато есть бессмысленная «0»;
* аудитории 4-го этажа в поиске подписаны как **«0 этаж»** (`_floorName` → `'$f этаж'`);
* маршрут на 4-й этаж не строится.

**Что делать:** починить данные (`"floor": 4`) и не давать молчаливому `?? 0`
маскировать ошибку — падать/логировать в debug-режиме:

```dart
final floorRaw = map['floor'];
if (floorRaw is! num) {
  throw FormatException('В $svgAsset отсутствует корректный "floor": $floorRaw');
}
```

Плюс тест: «все 6 JSON парсятся, номера этажей = {-1,1,2,3,4,5}, каждое ребро
ссылается на существующий узел».

### 3.2 Лестницы этажей 2–5 без метаданных → межэтажный маршрут невозможен

Проверка данных:

```
floor -1: stairs 5,  группы [B, D, I, J, K]
floor  1: stairs 12, группы [A..L]
floor  2: stairs 11, stairsGroupId/connectsFloors — отсутствуют у ВСЕХ 11
floor  3: stairs 7,  — отсутствуют у всех
floor  4: stairs 5,  — отсутствуют у всех
floor  5: stairs 1,  — отсутствует
```

`route_builder.dart:97-113` строит переход только при
`node.stairsGroupId != null` и совпадении группы на другом этаже. Значит
**физически возможны только переходы −1 ↔ 1**; из 3-го этажа на 4-й маршрут
всегда вернёт `null` → «Маршрут не найден» (`map_screen.dart:502`).

**Что делать:**

1. Заполнить `stairsGroupId` + `connectsFloors` для лестниц 2–5 (это данные, не код).
2. Пока данных нет — не показывать «Маршрут не найден» как тупик, а объяснять:
   «между этажами 2–5 маршрут пока не поддерживается».
3. Валидация графа при загрузке (debug): симметричность `connectsFloors`
   (`A.connectsFloors.contains(B)` ⇔ `B.connectsFloors.contains(A)`), отсутствие
   «висячих» рёбер, связность этажа.

Замечание для будущего редактора карт: `MapNode.id` (например `n_1`) **не уникален
между этажами** (`n_1` есть и на −1, и на 5). Любой глобальный индекс должен
ключеваться парой `(floor, id)` — сейчас это спасает только `_State` в A*.

### 3.3 Вес ребра — квадрат расстояния, а не расстояние

`map_models.dart:82-84`:

```dart
final dx = other.x - self.x;
final dy = other.y - self.y;
result.add((node: other, weight: (dx * dx + dy * dy)));  // квадрат!
```

A* минимизирует **сумму квадратов** длин сегментов. Это не «кратчайший путь»,
а «путь с минимумом длинных сегментов». На реальных данных `floor_1.json`:

* медианное ребро: 45 px → стоимость 2 025;
* самое длинное ребро: 158 px → стоимость 25 045;
* путь из 4 коротких сегментов по 50 px (200 px суммарно) стоит 10 000,
  то есть **дешевле одного прямого 158-px коридора**.

Итог: алгоритм может предпочесть более длинный ломаный маршрут прямому.

**Что делать:** `weight = sqrt(dx² + dy²)` (или сразу метры, если откалибровать
`imageWidth` под план здания). Тогда сумма длин = реальный метраж и появляется
смысл показывать «≈120 м / 2 мин».

```dart
result.add((node: other, weight: math.sqrt(dx * dx + dy * dy)));
```

### 3.4 Стоимость перехода по лестнице практически нулевая

`route_builder.dart:24`:

```dart
/// Чем выше, тем меньше переходов выберет алгоритм.
static const double stairTransitionCost = 500.0;
```

При весах в квадратных пикселях медианное ребро — **2 025**, то есть переход
на целый этаж дешевле четверти коридорного сегмента. Комментарий обещает
«меньше переходов», а по факту переход почти бесплатен.

**Что делать:** задать стоимость в единицах того же масштаба, что и рёбра
(после перехода на `sqrt` — «сколько метров эквивалентно подъёму на этаж»,
разумно 15–25 м на этаж):

```dart
static const double stairsCostPerFloor = 18.0; // «метров» на один этаж
...
yield _NextState(_State(f, other.id), stairsCostPerFloor * (f - s.floor).abs());
```

### 3.5 A*: приоритетная очередь с изменяемым ключом — путь может быть неоптимальным

`route_builder.dart:48-56, 66-74`:

```dart
final open = SplayTreeSet<_State>((a, b) {
  final fa = fScore[a] ?? double.infinity;   // ключ читается из внешней Map
  final fb = fScore[b] ?? double.infinity;
  ...
});
...
fScore[next.state] = tentativeG + _heuristic(next.state, endState);
open.add(next.state);   // элемент уже может быть в множестве!
```

`SplayTreeSet` требует **неизменяемых** ключей. Здесь `fScore[state]` меняется
у элемента, который уже лежит в дереве, а `add` повторно вставляет то же
состояние. Компаратор перестаёт считать пару равной → в множестве появляются
дубликаты в позициях, не соответствующих текущему `f`, и `open.first` возвращает
не тот узел. Классическая ошибка A*: алгоритм не падает, но выдаёт
неоптимальный маршрут (и, в теории, может зациклиться на пересчёте).

**Что делать:** куча с ленивым удалением устаревших записей:

```dart
class _QEntry implements Comparable<_QEntry> {
  final double f;
  final double g;
  final _State state;
  final int seq;
  _QEntry(this.f, this.g, this.state, this.seq);
  @override
  int compareTo(_QEntry o) => f != o.f ? f.compareTo(o.f) : seq.compareTo(o.seq);
}

final open = HeapPriorityQueue<_QEntry>();   // package:collection
final best = <_State, double>{startState: 0.0};
open.add(_QEntry(h(startState), 0, startState, _seq++));

while (open.isNotEmpty) {
  final e = open.removeFirst();
  if (e.g > (best[e.state] ?? double.infinity)) continue; // устаревшая запись
  if (e.state == endState) return _reconstruct(cameFrom, e.state, e.g);
  for (final next in _neighbors(e.state)) {
    final g = e.g + next.cost;
    if (g < (best[next.state] ?? double.infinity)) {
      best[next.state] = g;
      cameFrom[next.state] = e.state;
      open.add(_QEntry(g + _heuristic(next.state, endState), g, next.state, _seq++));
    }
  }
}
```

`seq` даёт детерминированный tie-break (сейчас tie-break по `hashCode` —
нестабильный между запусками).

### 3.6 `totalCost` всегда 0, `isTransition` никогда не выставляется

`route_builder.dart:153` — `return RouteResult(steps: steps, totalCost: 0);`
стоимость нигде не считается, хотя она нужна хотя бы для «≈ N м / M мин»
и для тестов «A* вернул оптимум».

`RouteStep.isTransition` (`:7`) и `_NextState.isTransition` (`:173`) объявлены,
но нигде не читаются и не выставляются → метка `// межэтажный переход`
в `RouteStep` всегда `false`, а `map_screen` её игнорирует. Это мёртвый код
(вероятное предупреждение линтера) и потерянная UX-возможность: подсказка
«здесь подняться по лестнице Б на 3-й этаж».

**Что делать:** возвращать `g` из `_reconstruct`, при сборке шагов помечать
шаги, где сменился этаж, и отображать это в панели маршрута.

### 3.7 Геометрия карты: `_screenToMap` не учитывает `fitScale`

`map_screen.dart:43-66`:

```dart
final unscaled = Offset(p.dx / _scale, p.dy / _scale);   // fitScale забыт
```

При этом `_mapToScreen` (`:227-249`) умножает на `total = fitScale * _scale`.
Функции не взаимно обратны: `_screenToMap` возвращает координаты, отличающиеся
в `1/fitScale` раз. На телефоне `fitScale ≈ 0.2`, то есть **в 5 раз**.

Второй слой проблемы: `Transform` на SVG (`:379-384`) масштабирует только на
`_scale`, а `SvgPicture` внутри `SizedBox(imageWidth × imageHeight)` с
`BoxFit.contain` дополнительно масштабируется сам. На экране **больше картинки**
(планшет, десктоп, web — папки `windows/`, `linux/`, `macos/`, `web/` есть)
`contain` даёт масштаб 1, а оверлей считает `fitScale > 1` → метки и линия
маршрута уезжают относительно плана.

Плюс мелочи рядом:

* `map_screen.dart:194` — `final focalScreen = _mapToScreen(focalMap, viewport, focalMap.dx, 0, 1.0);`
  считается и не используется (аргументы «заглушки»);
* `map_screen.dart:143` — `_routeBuilder!.findRoute(...)`: если все JSON не
  распарсились, `_routeBuilder` остаётся `null` → краш;
* `map_screen.dart:137-156` — `_recalcRoute()` вызывает `setState` внутри
  `setState` (`_pickFrom` → `setState(() { ...; _recalcRoute(); })`), плюс
  `_resetView()` — ещё один `setState` внутри.

**Что делать:** один immutable-класс трансформации, обратные операции и юнит-тесты
`toMap(toScreen(p)) ≈ p`:

```dart
@immutable
class MapTransform {
  const MapTransform({
    required this.viewport, required this.image,
    this.scale = 1, this.offset = Offset.zero, this.rotation = 0,
  });

  final Size viewport;
  final Size image;
  final double scale;
  final Offset offset;
  final double rotation;

  double get fitScale => math.min(
        viewport.width / image.width,
        viewport.height / image.height,
      );
  double get total => fitScale * scale;
  Offset get _center => Offset(image.width / 2, image.height / 2);
  Offset get _screenCenter => viewport.center(Offset.zero);

  Offset toScreen(Offset mapPoint) {
    final d = mapPoint - _center;
    final c = math.cos(rotation), s = math.sin(rotation);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) * total +
        _screenCenter + offset;
  }

  Offset toMap(Offset screenPoint) {
    final v = (screenPoint - _screenCenter - offset) / total;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c) + _center;
  }
}
```

Дальше SVG рисовать ровно в `image`-размере и применять ту же матрицу
(`..scale(transform.total)`), а ещё лучше — отдать жесты `InteractiveViewer`
с `TransformationController` и брать `controller.value` как единственный
источник истины (тогда бесплатно появляются инерция, double-tap zoom,
boundary-ограничения, которых сейчас нет).

### 3.8 Декодер windows-1251 теряет символы

`rating_session.dart:63-87`: байты 0x80–0xBF, кроме восьми перечисленных,
превращаются в `'?'`. В cp1251 в этом диапазоне, например:

* **0xB9 = `№`** — очень частый символ в шапке ведомости;
* 0xA0 = nbsp (есть), 0x96/0x97 (есть), а вот `Ў`, `Ј`, `Ґ`, `°`, `±`, `·` — нет.

То есть заголовки вида «№ зачётки» уже сейчас приходят с `?`. Дальше по цепочке
`'?'` попадает в ключи кэша и сравнения строк.

**Что делать:** не писать свой декодер. Либо `package:charset`
(`CharsetConverter.decode('windows-1251', bytes)`), либо полная таблица на 0x80–0xBF
(в коде — `const _cp1251High = <int, int>{...}`), причём неизвестный байт лучше
заменять на `\uFFFD`, а не на `?`, чтобы потеря была заметна.

Сюда же: `_extractHidden` (`:98-107`) ищет `name="..." value="..."` строго в этом
порядке и не раскодирует HTML-сущности (`&amp;`, `&#39;`). В проекте уже есть
`package:html` — разбирать ответ им, а не регуляркой:

```dart
final doc = html_parser.parse(html);
final v = doc.querySelector('input[name="__VIEWSTATE"]')?.attributes['value'];
```

### 3.9 `setState` после `dispose`

`rating_my_scores_screen.dart:37-87`: цикл `for (final s in widget.subjects)`
последовательно грузит ведомости и на каждой итерации делает
`setState(() => _loaded++)` (`:83`) и `setState(() => _scores.add(...))` (`:73`).
Если пользователь нажмёт «назад» во время загрузки — `setState() called after
dispose()`.

**Что делать:** проверка `if (!mounted) return;` перед каждым `setState`
(и отмена/игнор результата после `dispose`). Тот же паттерн стоит проверить в
`rating_screen._bootstrap` и `teacher_schedule_screen._initTeachers`.

### 3.10 Сессия ASP.NET «холодная» при старте из кэша

`rating_screen.dart:41-120`: если кэш факультетов/групп есть, `_service.init()`
(единственный GET, который получает cookies + `__VIEWSTATE`) **не вызывается**.
Позже `_loadOrFetchVedomost` → `fetchVedomost` → `GET Ved.aspx?id=...` уходит с
пустым `_viewState` и без cookies. Для ASP.NET WebForms это лотерея: часть
страниц отдаст `Runtime Error` / «Validation of viewstate MAC failed».

**Что делать:** прогревать сессию всегда (один лёгкий GET при старте — дешевле,
чем один упавший экран), либо сохранять cookies + `__VIEWSTATE` вместе с кэшем
и восстанавливать их. Второе правильнее: кэш должен описывать не только данные,
но и контекст, в котором они получены.

### 3.11 Парсер расписания: эвристика «вторая строка» теряет чётные недели

`schedule_parser.dart:170-189`:

```dart
final isSecondRow = existing != null &&
    existing.numerator.isNotEmpty &&      // ← ключевое условие
    existing.denominator.isEmpty;
```

Если у пары занятие только по знаменателю (чётная неделя), в первой строке
ячейка пустая → `existing` не создаётся (или `numerator` пуст) → значение
второй строки попадёт в **числитель**. Предмет окажется «не на той неделе».

**Что делать:** не угадывать по содержимому, а использовать структуру листа:
после строки со временем следующая строка — знаменатель. Читать явно
`row r` и `row r + 1`, затем перешагивать через неё:

```dart
if (currentDay.isEmpty || !_looksLikeTime(colB)) continue;
final numRow = row;
final denRow = (r + 1 < rows.length) ? rows[r + 1] : const <Data?>[];
// ... читаем num из numRow, den из denRow, потом r++ (skip denRow)
```

Плюс `catch (_) {}` в `:37` вокруг `getMergedCells` скрывает поломку API:
если метод перестанет работать, расписание «распарсится» без объединённых
ячеек и тихо станет неверным. Нужен лог + флаг «деградировали».

### 3.12 Dropdown: падение при смене списка и невидимый пункт «Все дни»

* `rating_screen.dart:133-137`: если выбранного факультета нет в новом списке,
  `orElse: () => _selectedFaculty!` возвращает **старый объект**, которого нет
  в `items`. `DropdownButtonFormField` в этом случае бросает
  assert «There should be exactly one item with value…». Правильно — сбросить
  в `null` при отсутствии.
* `teacher_schedule_screen.dart:159-163`: `DropdownMenuItem<String>(value: null)`
  для «Все дни». `DropdownButton` при `value == null` показывает `hint`,
  а не пункт с `null`, поэтому вместо «Все дни» пользователь видит пустое поле.
  Нужен сентинел `'__all__'` или `hint: Text('Все дни')`.
* Пустые `items` (`:160`) с `value: null` дают «все дни» только по факту.

### 3.13 Ведомость: колонка «Итог» — копия «Оценки», и индекс весов без проверки

`rating_vedomost_screen.dart:237-241`:

```dart
_dataCell(s.finalRating, ratingW, bold: true),
_dataCell(s.grade, gradeW, highlight: true),  // «Оценка»
_dataCell(s.grade, gradeW),                   // «Итог» — то же самое
```

Две колонки с одинаковым содержимым: похоже на недоделку (вероятно, «Итог»
должен быть итогом по ведомости / «зачтено-незачтено»).

`rating_vedomost_screen.dart:204-208` — `v.controlPoints[kt].weights[j]` для `j < 4`
без проверки длины. В кэше (`rating_service._vedomostFromJson`) длина не
валидируется, а в `ControlPoint` тип `List<int>`. Один битый/старый кэш →
`RangeError` и красный экран вместо таблицы.

**Что делать:** `weights.length` → `List.filled(4, 0)` при десериализации;
колонку «Итог» либо убрать, либо наполнить смыслом.

---

## 4. P1 — производительность

### 4.1 Парсинг Excel на UI-изоляте

`schedule_screen.dart:132-151`: `Excel.decodeBytes(_excelBytes!)` и
`ScheduleParser.parse(...)` — синхронно в `setState`-контексте. Файл факультета
это десятки тысяч ячеек; на среднем Android это сотни миллисекунд → заметный
фриз, а при `_onCourseSelected` (`:178-181`) — повторный полный `decodeBytes`
на каждый тап по курсу.

**Что делать:**

```dart
// bytes → ScheduleData в отдельном изоляте
final data = await compute(_parseScheduleInIsolate, (
  bytes: bytes, sheet: course, faculty: faculty,
));
```

где `_parseScheduleInIsolate` — top-level функция (в изолят передаются только
байты). Дополнительно кэшировать `ScheduleData` по `(faculty, course)`, чтобы
переключение курсов было мгновенным.

### 4.2 xlsx в base64 внутри SharedPreferences

`schedule_cache.dart:12-19`: `base64Encode(bytes)` в `prefs.setString`.
SharedPreferences на Android — это XML, который целиком читается в память при
первом обращении; base64 добавляет ещё +33 %, а кодирование/декодирование идёт
на UI-изоляте. Для 5 факультетов это несколько мегабайт «в строке».

**Что делать:** `path_provider` + файл в `ApplicationSupportDirectory`,
в `prefs` — только метаданные (`mtime`, `etag`, `версия`):

```dart
class ScheduleCache {
  Future<File> _file(String facultyKey) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/schedule');
    await dir.create(recursive: true);
    return File('${dir.path}/$facultyKey.xlsx');
  }

  Future<void> saveBytes(String key, Uint8List bytes) async {
    await (await _file(key)).writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> loadBytes(String key) async {
    final f = await _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }
}
```

### 4.3 `nodeById` — линейный поиск внутри обхода рёбер

`map_models.dart:63-87`: `neighbors()` для каждого ребра вызывает `nodeById`
(O(N)). На `floor_1.json` (174 узла / 177 рёбер) это ~30 тыс. операций на
раскрытие одного узла. Работает, но масштабируется квадратично.

**Что делать:** при загрузке строить индексы один раз:

```dart
class MapFloor {
  late final Map<String, MapNode> nodesById = {for (final n in nodes) n.id: n};
  late final Map<String, List<({String to, double cost})>> adjacency = /* ... */;
}
```

(и `late final` требует перенести создание в конструктор или фабрику).

### 4.4 Таблица расписания: `setState` на каждый пиксель скролла + нет ленивости

`schedule_screen.dart:48-55`:

```dart
_bodyScrollController.addListener(() {
  if ((newOffset - _horizontalScroll).abs() > 0.5) {
    setState(() => _horizontalScroll = newOffset);   // перестройка всей таблицы
  }
});
```

Каждое событие скролла перестраивает ~600 строк build-логики (включая
`_measureTextHeight` через `TextPainter` для каждой ячейки!). Плюс `Column`
со всеми строками (`:509`) — без `ListView.builder`, всё строится сразу.

**Что делать:**

* синхронизировать шапку и тело через `TransformationController`/
  `ScrollController`-пару (или `linked_scroll_controller`), а не через `setState`;
  либо `AnimatedBuilder(animation: controller)` вокруг одной шапки;
* вынести `_rowHeight` в предрасчёт при парсинге (один раз), а не в `build`;
* `ListView.builder` по строкам с зафиксированной высотой из предрасчёта;
* убрать ручную геометрию в пользу `Table`/`DataTable2` (зависимость уже
  в `pubspec.yaml`, но **не используется**).

### 4.5 Всё грузится на старте

`main.dart:66-71`: `IndexedStack` строит все четыре экрана сразу, поэтому при
запуске одновременно: `MapScreen._load()` (6 JSON + 6 SVG), `RatingScreen._bootstrap()`
(сеть или кэш), `TeacherScheduleScreen` (не строится, но `ScheduleScreen`
инициирует чтение кэша). Пользователь, открывший «Расписание», платит за сеть
рейтинга.

**Что делать:** ленивая инициализация вкладок (создавать экран при первом
посещении и дальше держать в `IndexedStack`/`AutomaticKeepAliveClientMixin`),
либо `PageView` + `AutomaticKeepAlive`.

### 4.6 Последовательные HTTP-запросы

* `rating_my_scores_screen.dart:45-84` — 10+ предметов строго последовательно;
* `rating_service.findMyScores` (`:87-116`) — то же самое, но метод вообще не
  используется (мёртвый код, дублирующий логику экрана);
* `rating_screen.dart:241-278` — ради списка зачёток скачивается **целая
  ведомость** первого предмета.

**Что делать:** ограниченный параллелизм (`Pool(4)` / `Future.wait` чанками по 4),
а список зачёток брать из уже закэшированной ведомости, а не тянуть новую.

### 4.7 Перерисовка маршрута каждый кадр и «ручные» метки

* `map_screen.dart:569-570`: `shouldRepaint` сравнивает `List<Offset>` по
  идентичности (`old.points != points`), а список создаётся заново в `build` →
  `true` всегда → перерисовка на каждый кадр.
* `:322-370`: на каждый узел этажа создаётся `Stack` из двух `Text` (обводка +
  заливка), до ~100 узлов. Ширина метки оценивается как
  `label.length * fontSize * 0.6 + 8` — для длинных подписей это промах,
  и метки наезжают друг на друга; при `_scale = 0.05` они полностью
  перекрываются.

**Что делать:** рисовать подписи в `CustomPainter` с кэшем `TextPainter`,
включать их только при `scale > порога` (level-of-detail), а `shouldRepaint`
сравнивать по `listEquals` + `repaint: ValueNotifier`. Обернуть карту в
`RepaintBoundary`.

---

## 5. P1 — надёжность сети и кэша

### 5.1 Нет таймаутов

Ни один запрос не задаёт `timeout`: `rating_session.dart:19,36`,
`teacher_service.dart:33`, `schedule_screen.dart:107`. При «плохом» Wi-Fi
спиннер крутится бесконечно (кнопки при этом блокируются флагами `_loading`).

```dart
final response = await http.get(uri, headers: _headers())
    .timeout(const Duration(seconds: 15));
```

Плюс единый `http.Client` на сервис (сейчас на каждый вызов создаётся новый
клиент → нет переиспользования соединений, `Connection: keep-alive` бесполезен),
ретраи с backoff для идемпотентных GET, и различение «нет сети» / «сервер 5xx» /
«сменилась вёрстка» в UI.

### 5.2 Пустые `catch` глотают всё

`rating_service.dart:113`, `rating_my_scores_screen.dart:82`, `map_loader.dart:24`,
`schedule_cache.dart:28`, `schedule_parser.dart:37`, `teacher_service.dart:57,82`.
Итог: при поломке парсера пользователь видит пустой экран и не может сообщить,
что именно сломалось; в логах — тишина.

**Что делать:** типизированные исключения (`NetworkException`,
`ParseException`, `CacheException`) + `debugPrint`/логгер + необязательный
crash-репортинг. `catch (_) {}` оставить только там, где есть явный fallback,
и с комментарием почему.

### 5.3 Кэш без TTL и без версии схемы

`loadUpdatedAt` есть везде (`schedule_cache.dart:34`, `teacher_service.dart:102`,
`rating_service.dart:135`), но используется **только для отображения даты**.
Ни один кэш не устаревает: расписание, скачанное в сентябре, показывается в
декабре, пока пользователь не нажмёт «обновить».

Отдельная проблема — **версия схемы**: `_ckVedomost` ключи не содержат версии
парсера. После исправления парсера (например, 3.8/3.11) старые кривые данные
живут в кэше у пользователей до ручной очистки.

**Что делать:**

```dart
const cacheSchemaVersion = 2;
String _key(String raw) => 'v$cacheSchemaVersion:$raw';
static const freshFor = Duration(hours: 6);
bool isFresh(DateTime at) => DateTime.now().difference(at) < freshFor;
```

Стратегия: показываем кэш сразу (stale-while-revalidate), в фоне обновляем,
помечаем «данные от 03.11, обновляются…».

### 5.4 Ключи `shared_preferences` утекают в UI

`rating_screen.dart:152-153`:

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.remove('rating_sel_group');   // дублирует приватную константу сервиса
```

Строка-ключ продублирована в виджете рядом с `rating_service._ckSelGroup`.
Разъедется при первом же переименовании. Нужен метод сервиса
`clearSelectedGroup()`.

### 5.5 `clearCache()` у рейтинга удаляет слишком много/мало

`rating_service.dart:314-320`: удаляются все ключи с префиксом `rating_`, включая
`rating_sel_*` (выбор пользователя). При этом кнопка «обновить» в
`rating_screen.dart:294-305` вызывает `clearCache()` + три последовательных
сетевых запроса. Пользователь теряет выбор группы просто потому, что нажал
«обновить».

---

## 6. P2 — архитектура и качество кода

### 6.1 Слои и внедрение зависимостей

Сервисы создаются прямо в `State` (`rating_screen.dart:19`,
`teacher_schedule_screen.dart:15`, `schedule_screen.dart:29`) — их нельзя
подменить в тестах. Предложение: один `AppScope` (InheritedWidget) или
`Provider`/`get_it` с тремя сервисами; тесты получают фейки.

### 6.2 Состояние экрана — 5 независимых `bool` + `String _error`

`rating_screen.dart:28-33` (`_loadingFaculties`, `_loadingGroups`,
`_loadingSubjects`, `_error`, `_lastUpdated`) и такое же в
`teacher_schedule_screen.dart`, `schedule_screen.dart`. Это 2^n невалидных
состояний, из которых половина невозможна. Один `sealed class`:

```dart
sealed class UiState<T> {}
class Loading<T> extends UiState<T> {}
class Data<T> extends UiState<T> { final T value; final DateTime updatedAt; final bool isStale; }
class Failure<T> extends UiState<T> { final String message; final Object? cause; }
```

### 6.3 Дублирование

* `_gradeColor` — `rating_my_scores_screen.dart:224` и `rating_vedomost_screen.dart:307`;
* `_formatDt` — 3 реализации (`schedule_screen.dart:205`, `teacher_schedule_screen.dart:292`,
  `rating_screen.dart:420`);
* `_capitalizeDay` — метод (`teacher_schedule_screen.dart:286`) **и** top-level
  функция с тем же именем (`:298`), которая нигде не используется
  (вероятное предупреждение `unused_element`);
* `_LessonCell` в `schedule_parser.dart:314-331` — почти полная копия
  `LessonCell` из `models/schedule.dart` (+ `_convertLessons` на 23 строки).
  Достаточно `LessonCell.copyWith(...)` или `mutable`-билдера.

Вынести в `lib/ui/format.dart` и `lib/ui/grades.dart`.

### 6.4 Мёртвый код и неиспользуемые вещи

| Что | Где |
|---|---|
| `_computeTopHeight` не вызывается | `schedule_screen.dart:185-203` |
| `LessonCell.hasTwoWeeks` не используется | `models/schedule.dart:52` |
| `ScheduleData.groups` не используется (есть `groupCols`) | `models/schedule.dart:4` |
| `RatingService.findMyScores` не используется | `rating_service.dart:87-116` |
| `RouteStep.isTransition`, `_NextState.isTransition` | `route_builder.dart:7,173` |
| `focalScreen` (локальная переменная) | `map_screen.dart:194` |
| `data_table_2` в зависимостях, но не импортируется | `pubspec.yaml:39` |
| top-level `_capitalizeDay` | `teacher_schedule_screen.dart:298` |

Ещё: `schedule_screen.dart:93-100` — `baseUrl.replaceAll('.xlsx','1.xlsx')`, а затем
`baseUrl.replaceAll('1.xlsx','.xlsx')` от исходной строки даёт тот же URL
(третий кандидат всегда дубликат первого). Намерение («иногда файл называется
`uits1.xlsx`») стоит оформить явно.

### 6.5 Модели: ручная сериализация 250 строк

`rating_service.dart:257-311` — ручные `_vedomostToJson/_vedomostFromJson` с
`as String`/`as int` кастами. Любое изменение модели — правка в двух местах,
любой старый кэш — `TypeError`. `Faculty`/`Group`/`Subject`/`TeacherLesson`
сериализуются вручную ещё в 4 местах.

**Что делать:** `freezed` + `json_serializable` (или хотя бы `json_serializable`)
дают `fromJson`/`toJson`, `copyWith`, `==`, и `tryParse`-безопасность.
Это сразу закрывает 6.3 (`_LessonCell`), 6.4 и половину 3.13.

### 6.6 Один виджет = 750 строк

`schedule_screen.dart` содержит и загрузку, и разбор, и таблицу, и стили ячеек.
Разбить хотя бы на:

```
screens/schedule/schedule_screen.dart        // состояние и загрузка
screens/schedule/schedule_table.dart         // сетка
screens/schedule/schedule_cells.dart         // _twoLineCell / _timeCell / ...
screens/schedule/schedule_controller.dart    // ChangeNotifier
```

### 6.7 Строки в коде

Все подписи «Расписание», «Выберите группу», «Маршрут не найден» — литералами в
виджетах. Для одного вуза это терпимо, но для тестов (`find.text`) и будущей
локализации лучше `lib/l10n/strings.dart` с константами либо ARB-файлы.

---

## 7. P2 — UI/UX и доступность

### 7.1 Нет русской локализации Material

`main.dart:28-47` — `MaterialApp` без `localizationsDelegates` и
`supportedLocales`. Следствие: контекстное меню `TextField` («Cut/Copy/Paste/
Select all»), кнопки диалогов и семантические подписи — **на английском**.

```dart
import 'package:flutter_localizations/flutter_localizations.dart';

MaterialApp(
  locale: const Locale('ru'),
  supportedLocales: const [Locale('ru')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  ...
)
```

### 7.2 Игнорируется системный размер шрифта

Вся таблица расписания и ведомости построена на `fontSize: 11/10`
и **ручном** измерении высоты через `TextPainter` без `textScaler`
(`schedule_screen.dart:553-561`). При системном увеличении шрифта (доступность)
текст обрезается, потому что высоты посчитаны для масштаба 1.0.

```dart
final tp = TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
  textScaler: MediaQuery.textScalerOf(context),   // ← добавить
)..layout(maxWidth: width);
```

### 7.3 Диалог поиска с фиксированным размером

`search_picker_dialog.dart:99-105`: `SizedBox(width: 400, height: 500)` поверх
`insetPadding: 16`. На телефоне шириной 320 dp (или при открытой клавиатуре с
`autofocus: true`) — `RenderFlex overflowed`. Нужно
`ConstrainedBox` + `Dialog` с `insetPadding` и учётом `viewInsets.bottom`,
или `showModalBottomSheet` (на телефоне удобнее).

### 7.4 Метки карты не читаются

`map_screen.dart:336-338` — ширина подписи оценивается по числу символов;
при 100 подписях на этаже они наезжают друг на друга, а на минимальном зуме
(`_scale` доходит до 0.05) превращаются в серое пятно. Нужен LOD: подписи только
для «крупных» зумов, приоритет подписи по типу узла, и `TextPainter` вместо
`length * 0.6`.

### 7.5 Продуктовые улучшения, которые просятся сами

Функции кажутся очевидными, а их нет — и они дают больше, чем любой рефакторинг:

1. **«Маршрут до пары» из расписания.** В ячейке расписания — иконка
   `directions`, открывает карту с уже заполненными `from = вход` / `to = аудитория`.
   Сейчас пользователь вручную ищет «а. 202» в списке.
2. **Тап по аудитории на карте** → «Отсюда» / «Сюда» (сейчас только через
   выпадающий поиск).
3. **Моя текущая позиция**: локальный QR/NFC на входе или просто «я на 1 этаже
   у входа» как старт по умолчанию (`_fromNode` сейчас всегда `null`).
4. **Поиск по номеру аудитории с этажом** (`202`, `2 этаж`) — сейчас поиск
   только по подписи.
5. **Оценка пути**: «≈120 м, 2 мин, 1 переход по лестнице» — нужно только
   вернуть `totalCost` (см. 3.6).
6. **Поиск своей зачётки по ФИО.** `rating_parser.dart:170` читает `tds[2]`
   как зачётку, а `tds[1]` (ФИО) **игнорируется**. Из-за этого пользователь
   выбирает себя из списка безликих номеров (`rating_screen.dart:245-265`).
   Распарсить ФИО → `StudentRow.name` и искать по нему — маленькая правка,
   большой эффект.
7. **Слияние источников**: расписание преподавателя знает `room` и `groups`,
   расписание студентов — ту же аудиторию. Перекрёстная ссылка
   «пара → аудитория → карта» уже почти есть в данных.
8. **Уведомление/виджет «следующая пара»** — данные для этого уже кэшируются.

### 7.6 Настройки

`settings_screen.dart`: нет ни «очистить кэш» (единственный способ — вручную
жать «обновить» на каждом экране), ни «мой факультет/группа/зачётка» (сейчас
выбор хранится, но поменять его можно только через экран рейтинга). Версия
`1.0.0` захардкожена (`:52-55`) — использовать `package_info_plus`.

### 7.7 Устаревший Material API (Flutter 3.47)

* `DropdownButtonFormField(value: ...)` — **deprecated** после 3.33,
  использовать `initialValue` (с `key: ValueKey(...)`, чтобы контролируемо
  обновлять) — `rating_screen.dart:332`, `teacher_schedule_screen.dart:152`,
  `schedule_screen.dart:286`;
* `RadioListTile(groupValue:, onChanged:)` — **deprecated** после 3.32, нужен
  `RadioGroup` — `settings_screen.dart:24-42`;
* `Color.withOpacity` — **deprecated**, `withValues(alpha: 0.5)` —
  `rating_vedomost_screen.dart:276`.

Это даст предупреждения `flutter analyze` прямо сейчас.

---

## 8. Тесты

Сейчас: `test/widget_test.dart` — стандартный шаблон «Counter» из
`flutter create`, обращающийся к `find.text('0')` и `Icons.add`, которых в
приложении нет. То есть **`flutter test` падает на первом же запуске**, и
единственный имеющийся тест проверяет несуществующее поведение.

Что стоит покрыть (все — чистые функции, изоляты не нужны):

| Тест | Вход | Ожидание |
|---|---|---|
| `schedule_parser_test.dart` | xlsx-фикстура в `test/fixtures/` | дни, группы, подгруппы, числитель/знаменатель |
| `schedule_parser_test.dart` | лист, где занятие только в знаменателе | значение в `denominator`, не в `numerator` (3.11) |
| `rating_parser_test.dart` | сохранённый HTML ведомости | ФИО, зачётки, КТ, веса |
| `rating_session_test.dart` | байты cp1251 | `№`, `–`, `«»` декодируются (3.8) |
| `route_builder_test.dart` | синтетический граф 3 этажа | кратчайший путь, число переходов, `totalCost` |
| `route_builder_test.dart` | граф с «прямым» 158px ребром и 4×50px | выбирается прямой путь (3.3) |
| `map_transform_test.dart` | `toMap(toScreen(p)) == p` | обратимость при разных scale/rotation (3.7) |
| `map_loader_test.dart` | все 6 JSON из assets | этажи `{-1,1,2,3,4,5}`, рёбра валидны (3.1, 3.2) |
| `schedule_cache_test.dart` | save/load | байты совпадают, TTL истекает (5.3) |

Пример для A* (проверяет заодно 3.3 и 3.5):

```dart
test('выбирает прямую, а не ломаную', () {
  // A--B: 158 px; A--C--D--E--B: 4 × 50 px
  final result = RouteBuilder(floors).findRoute(
    startFloor: 1, startNodeId: 'a', endFloor: 1, endNodeId: 'b');
  expect(result!.steps.map((s) => s.node.id), ['a', 'b']);
  expect(result.totalCost, closeTo(158, 0.5));
});
```

CI: `.github/workflows/ci.yml` с `flutter analyze --fatal-infos` и
`flutter test` на каждый push. Сейчас нет ни директории `.github`, ни git —
см. следующий раздел.

---

## 9. Инфраструктура и релиз

1. **Нет git.** `git init`, коммит текущего состояния, `.gitignore` уже есть;
   `build/` и `.dart_tool/` сейчас лежат в рабочей папке.
2. **`applicationId = "com.example.vguit_app"`** и релизная сборка, подписанная
   **debug-ключом** (`android/app/build.gradle.kts`). С таким приложением в
   RuStore/Google Play делать нечего: нужен `ru.vsuet.vguit` (или что выдаст вуз),
   `signingConfig` с keystore, `key.properties` вне репозитория.
3. **`android:label="vguit_app"`** — на иконке в лончере так и будет «vguit_app».
   Поставить «ВГУИТ Студент».
4. `pubspec.yaml:2` — `description: "A new Flutter project."`, `README.md` —
   шаблон. Для проекта, который читают другие люди (и преподаватели), нужен
   README: источники данных, как обновлять `assets/map/*.json`, как запускать тесты.
5. **Нет версионирования кэша** при изменении парсеров (см. 5.3).
6. Мелкое: `analysis_options.yaml` наследует `flutter_lints`, но ничего не
   добавляет; стоит включить `always_declare_return_types`,
   `prefer_final_locals`, `unawaited_futures` (последний поймал бы часть
   «забытых» асинхронных вызовов), `require_trailing_commas`.

---

## 10. План работ

**Итерация 1 — «чтобы не врало» (1–2 дня)**

* [ ] `floor_4.json`: `"floor": 4`; метаданные лестниц для этажей 2–5 (данные).
* [ ] Веса рёбер → `sqrt`, стоимость лестницы в тех же единицах (3.3, 3.4).
* [ ] A* на `HeapPriorityQueue` + `totalCost` (3.5, 3.6).
* [ ] `if (!mounted)` в асинхронных циклах (3.9).
* [ ] `fitScale` в `_screenToMap` / `MapTransform` (3.7).
* [ ] Полный cp1251 (3.8).
* [ ] Удалить мёртвый код, починить/удалить `widget_test.dart` (6.4, 8).

**Итерация 2 — «чтобы не висло» (3–5 дней)**

* [ ] Таймауты, единый `http.Client`, ретраи, типизированные ошибки (5.1, 5.2).
* [ ] xlsx-кэш в файл, TTL + версия схемы (4.2, 5.3).
* [ ] Парсинг xlsx через `compute`, кэш `ScheduleData` по (факультет, курс) (4.1).
* [ ] Ленивые вкладки, `ListView.builder` в расписании, скролл без `setState` (4.4, 4.5).
* [ ] Тесты на парсеры и A* + CI (8).

**Итерация 3 — «чтобы было приятно»**

* [ ] `freezed`/`json_serializable` для моделей (6.5).
* [ ] Локализация `ru`, `textScaler`, семантика, размеры диалогов (7.1–7.4).
* [ ] Распилить `schedule_screen.dart` (6.6); DI через `AppScope` (6.1).
* [ ] Продуктовые фичи: маршрут из расписания, тап по аудитории, ФИО в ведомости,
  «очистить кэш» в настройках (7.5, 7.6).
* [ ] Релизная инфраструктура: applicationId, подпись, label, README (9).

---

## Приложение A. Готовый минимальный каркас `RouteBuilder`

Показывает сразу 3.3, 3.4, 3.5, 3.6 и часть 4.3 (требует `package:collection`):

```dart
import 'dart:collection';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import '../models/map_models.dart';

class RouteStep {
  final int floor;
  final MapNode node;
  final bool isTransition;
  const RouteStep({required this.floor, required this.node, this.isTransition = false});
}

class RouteResult {
  final List<RouteStep> steps;
  final double totalCost;   // в «метрах» (px * 0.05, если откалибровано)
  const RouteResult({required this.steps, required this.totalCost});
}

class RouteBuilder {
  RouteBuilder(this.floors);

  final Map<int, MapFloor> floors;

  /// Стоимость подъёма на один этаж в единицах длины рёбер.
  static const double stairsCostPerFloor = 18.0;

  final _nodes = <String, MapNode>{};          // ключ: '$floor/${id}'
  final _adj = <String, List<({String to, double cost, bool stairs})>>{};

  void _ensureIndex() {
    if (_adj.isNotEmpty) return;
    for (final f in floors.values) {
      for (final n in f.nodes) {
        _nodes['${f.floor}/${n.id}'] = n;
      }
      for (final n in f.nodes) {
        final key = '${f.floor}/${n.id}';
        for (final e in f.edges) {
          final otherId = e.from == n.id ? e.to : (e.to == n.id ? e.from : null);
          if (otherId == null) continue;
          final other = f.nodeById(otherId);   // см. 4.3 — здесь нужен индекс
          if (other == null) continue;
          final cost = math.sqrt(math.pow(other.x - n.x, 2) + math.pow(other.y - n.y, 2));
          (_adj[key] ??= []).add((to: '$key/$otherId', cost: cost, stairs: false));
        }
      }
    }
    // межэтажные связи по группам лестниц
    final byGroup = <String, List<MapNode>>{};
    for (final f in floors.values) {
      for (final n in f.nodes) {
        if (n.type == MapNodeType.stairs && n.stairsGroupId != null) {
          (byGroup[n.stairsGroupId!] ??= []).add(n);
        }
      }
    }
    // ... соединить узлы одной группы между этажами с весом stairsCostPerFloor * |Δэтаж|
  }

  RouteResult? findRoute({
    required int startFloor, required String startNodeId,
    required int endFloor, required String endNodeId,
  }) { /* цикл A* из 3.5, затем _reconstruct(..., g[end]) */ }
}
```

## Приложение B. Итоговая оценка

| Область | Оценка | Комментарий |
|---|---|---|
| Структура проекта | 4/5 | слои есть, но экраны перегружены |
| Модели данных | 3/5 | ручная сериализация, дубли, `null`-терпимость |
| Парсеры | 3/5 | работают, но на эвристиках и без тестов |
| Карта и маршрут | 2/5 | сильная идея, но данные и геометрия ломают результат |
| Работа с сетью | 2/5 | нет таймаутов, ошибки глотаются |
| Кэширование | 2/5 | есть, но без TTL/версии и с base64 в prefs |
| UI/UX | 3/5 | аккуратно, но без локализации и доступности |
| Тесты | 1/5 | единственный тест падает |
| Релиз | 1/5 | `com.example`, debug-подпись, нет git |

Основной вывод: **код структурно здоровый**, главные потери — не в стиле,
а в трёх местах: (1) данные карты и геометрия маршрута, (2) отсутствие
таймаутов/типизированных ошибок/тестов, (3) кэш без TTL и версии схемы.
Исправление этих трёх блоков даёт ощутимый прирост качества при умеренном объёме работ.