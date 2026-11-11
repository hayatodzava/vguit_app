import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'net.dart';

/// Сессия для ASP.NET WebForms.
///
/// Хранит cookies и **всё состояние формы** (скрытые поля и выбранные
/// значения выпадающих списков). Postback собирается из того, что сервер
/// реально отрисовал: отправлять туда произвольные значения нельзя —
/// ASP.NET отвечает 500 «Ошибка выполнения».
class RatingSession {
  RatingSession();

  static const String baseUrl = 'https://rating.vsuet.ru/web/ved';

  final Map<String, String> _cookies = <String, String>{};
  final Map<String, String> _fields = <String, String>{};

  /// Последняя страница с формой — из неё берём списки значений.
  String? _lastPage;

  Map<String, String> get cookies => Map<String, String>.unmodifiable(_cookies);

  /// Состояние формы, полученное с последней страницы.
  Map<String, String> get fields => Map<String, String>.unmodifiable(_fields);

  bool get hasCookies => _cookies.isNotEmpty;

  /// Есть ли с чем отправлять postback.
  bool get hasFormState => (_fields['__VIEWSTATE'] ?? '').isNotEmpty;

  /// HTML последней страницы с формой.
  String? get lastPage => _lastPage;

  /// Полное имя поля формы по суффиксу (`cmbFacultets` и т.п.).
  String? fieldName(String suffix) {
    for (final key in _fields.keys) {
      if (key == suffix || key.endsWith('\$$suffix')) return key;
    }
    return null;
  }

  /// Значение поля формы по суффиксу имени.
  String? fieldValue(String suffix) => _fields[fieldName(suffix) ?? ''];

  /// Все варианты выпадающего списка с последней страницы.
  ///
  /// Нужны, чтобы не отправлять в postback значение, которого нет в списке:
  /// ASP.NET отвечает на такое 500 «Ошибка выполнения».
  List<({String value, String label})> options(String suffix) {
    final html = _lastPage;
    if (html == null) return const <({String value, String label})>[];
    final doc = html_parser.parse(html);
    for (final select in doc.querySelectorAll('select[name]')) {
      final name = select.attributes['name'] ?? '';
      if (name != suffix && !name.endsWith('\$$suffix')) continue;
      return select
          .querySelectorAll('option')
          .map(
            (option) => (
              value: option.attributes['value'] ?? '',
              label: option.text.trim(),
            ),
          )
          .toList(growable: false);
    }
    return const <({String value, String label})>[];
  }

  bool hasOption(String suffix, String value) {
    final variants = options(suffix);
    return variants.isEmpty || variants.any((option) => option.value == value);
  }

  /// GET-запрос с сохранением cookies и состояния формы.
  Future<String> get(String url, {String? action}) async {
    final response = await httpGet(
      Uri.parse(url),
      headers: _headers(),
      action: action,
    );
    _saveCookies(response);
    return _read(response);
  }

  /// POST-postback: к состоянию формы добавляются только изменения.
  Future<String> post(
    String url,
    Map<String, String> overrides, {
    String? action,
  }) async {
    if (!hasFormState) {
      throw AppException(
        'Сайт рейтинга не отдал форму (нет __VIEWSTATE). '
        'Попробуйте обновить ещё раз.',
        kind: AppErrorKind.parse,
      );
    }

    final body = <String, String>{
      '__EVENTTARGET': '',
      '__EVENTARGUMENT': '',
      '__LASTFOCUS': '',
      ..._fields,
      ...overrides,
    };

    final response = await httpPost(
      Uri.parse(url),
      headers: _headers(isPost: true),
      body: body,
      action: action,
    );
    _saveCookies(response);
    return _read(response);
  }

  /// Обновить состояние формы из HTML после ответа.
  ///
  /// Обновляем только со страницы со списком (там есть `cmbFacultets`).
  /// Страница ведомости приносит свой `__VIEWSTATE`, и postback на
  /// Default.aspx с ним падает с 500 — а заодно затирал бы список предметов,
  /// который мы берём из последней страницы списка.
  void updateForm(String html) {
    final doc = html_parser.parse(html);

    if (doc.querySelector('select[name\$="cmbFacultets"]') == null) return;

    final viewState =
        doc.querySelector('input[name="__VIEWSTATE"]')?.attributes['value'] ??
        '';
    if (viewState.isEmpty) return;

    final next = <String, String>{};

    for (final input in doc.querySelectorAll('input[name]')) {
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type != 'hidden') continue;
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      next[name] = input.attributes['value'] ?? '';
    }

    // Выбранные значения списков — то, что браузер отправил бы обратно.
    for (final select in doc.querySelectorAll('select[name]')) {
      final name = select.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final options = select.querySelectorAll('option');
      if (options.isEmpty) continue;
      final selected = options.firstWhere(
        (option) => option.attributes.containsKey('selected'),
        orElse: () => options.first,
      );
      next[name] = selected.attributes['value'] ?? '';
    }

    _fields
      ..clear()
      ..addAll(next);

    _lastPage = html;
  }

  /// Декодирует тело с учётом кодировки из Content-Type.
  /// По умолчанию — windows-1251 (так отдаёт сайт ВГУИТ).
  String _read(http.Response response) {
    final body = _decodeBody(response);
    updateForm(body);
    return body;
  }

  String _decodeBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    final match = RegExp(r'charset=([\w-]+)').firstMatch(contentType);
    final charset = match?.group(1)?.toLowerCase() ?? 'windows-1251';

    if (charset == 'utf-8' || charset == 'utf8') {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    return _decodeWindows1251(response.bodyBytes);
  }

  /// Простой декодер windows-1251 → Unicode для кириллицы.
  /// Покрывает буквы А-я, Ё, ё и стандартную пунктуацию.
  String _decodeWindows1251(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buffer.writeCharCode(b);
      } else if (b >= 0xC0 && b <= 0xFF) {
        // А-я
        buffer.writeCharCode(0x0410 + (b - 0xC0));
      } else {
        // Остальные символы (Ё, ё, пунктуация)
        const map = <int, int>{
          0xA8: 0x0401, // Ё
          0xB8: 0x0451, // ё
          0x96: 0x2013, // –
          0x97: 0x2014, // —
          0xAB: 0x00AB, // «
          0xBB: 0x00BB, // »
          0x85: 0x2026, // …
          0xA0: 0x00A0, // nbsp
        };
        buffer.writeCharCode(map[b] ?? 0x003F); // ? если не знаем
      }
    }
    return buffer.toString();
  }

  void _saveCookies(http.Response response) {
    final raw = response.headersSplitValues['set-cookie'];
    if (raw == null || raw.isEmpty) return;

    for (final part in raw) {
      final kv = part.split(';').first.trim();
      if (kv.isEmpty) continue;
      final eq = kv.indexOf('=');
      if (eq > 0) {
        final name = kv.substring(0, eq).trim();
        final value = kv.substring(eq + 1).trim();
        _cookies[name] = value;
      }
    }
  }

  Map<String, String> _headers({bool isPost = false}) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 16; Pixel 10) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36',
      'Accept-Language': 'ru,en;q=0.9',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Connection': 'keep-alive',
    };
    if (isPost) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      headers['Origin'] = 'https://rating.vsuet.ru';
      headers['Referer'] = '$baseUrl/Default.aspx';
      headers['Upgrade-Insecure-Requests'] = '1';
    }
    if (_cookies.isNotEmpty) {
      headers['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    return headers;
  }
}
