import 'dart:async';

import 'package:http/http.dart' as http;

/// Категория ошибки — от неё зависит текст в диалоге.
enum AppErrorKind { network, timeout, server, parse, cache, unknown }

/// Ошибка с понятным пользователю текстом.
///
/// Все слои (сеть, парсеры, кэш) приводят свои исключения к этому типу,
/// чтобы в интерфейсе можно было показать причину, а не «Exception: ...».
class AppException implements Exception {
  AppException(this.message, {this.kind = AppErrorKind.unknown, this.cause});

  /// Текст для пользователя.
  final String message;

  final AppErrorKind kind;

  /// Исходное исключение — для подробностей в диалоге.
  final Object? cause;

  String? get details {
    final source = cause;
    if (source == null) return null;
    final text = source.toString();
    return text == message ? null : text;
  }

  @override
  String toString() => message;

  /// Приводит любое исключение к понятному тексту.
  ///
  /// [action] — что делали в момент ошибки, например «Загрузка расписания».
  static AppException from(Object error, {String? action}) {
    if (error is AppException) return error;
    final prefix = action == null ? '' : '$action: ';

    if (error is TimeoutException) {
      return AppException(
        '$prefixсервер не ответил за ${kRequestTimeout.inSeconds} секунд. '
        'Проверьте интернет и попробуйте ещё раз.',
        kind: AppErrorKind.timeout,
        cause: error,
      );
    }
    if (error is http.ClientException) {
      return AppException(
        '$prefixне удалось соединиться с сервером. '
        'Попробуйте позже.',
        kind: AppErrorKind.network,
        cause: error,
      );
    }
    // SocketException/HttpException из dart:io не импортируем, чтобы
    // файл собирался и под web; проверяем по имени типа.
    final typeName = error.runtimeType.toString();
    if (typeName == 'SocketException' || typeName == 'HttpException') {
      return AppException(
        '$prefixнет подключения к интернету. '
        'Проверьте сеть и повторите попытку.',
        kind: AppErrorKind.network,
        cause: error,
      );
    }
    if (error is FormatException || error is TypeError) {
      return AppException(
        '$prefixполучены данные в неожиданном формате. '
        'Вероятно, сайт изменился — сообщите об этом разработчику.',
        kind: AppErrorKind.parse,
        cause: error,
      );
    }
    return AppException(
      '$prefixчто-то пошло не так. Попробуйте ещё раз.',
      cause: error,
    );
  }

  /// Ошибка разбора файла расписания.
  static AppException parse(String message, {Object? cause}) =>
      AppException(message, kind: AppErrorKind.parse, cause: cause);

  /// Ошибка работы с кэшем.
  static AppException cache(String message, {Object? cause}) =>
      AppException(message, kind: AppErrorKind.cache, cause: cause);
}

/// Таймаут обычного запроса.
const Duration kRequestTimeout = Duration(seconds: 15);

/// Таймаут скачивания файла (xlsx бывает большим).
const Duration kDownloadTimeout = Duration(seconds: 40);

/// Общий клиент: переиспользует соединения между запросами.
final http.Client _client = http.Client();

/// GET с таймаутом и понятной ошибкой.
Future<http.Response> httpGet(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = kRequestTimeout,
  String? action,
}) {
  return _send(
    () => _client.get(uri, headers: headers).timeout(timeout),
    action: action,
  );
}

/// POST с таймаутом и понятной ошибкой.
Future<http.Response> httpPost(
  Uri uri, {
  Map<String, String>? headers,
  Map<String, String>? body,
  Duration timeout = kRequestTimeout,
  String? action,
}) {
  return _send(
    () => _client.post(uri, headers: headers, body: body).timeout(timeout),
    action: action,
  );
}

/// Скачивание файла: отдельный, более длинный таймаут.
Future<http.Response> httpDownload(
  Uri uri, {
  Map<String, String>? headers,
  String? action,
}) {
  return _send(
    () => _client.get(uri, headers: headers).timeout(kDownloadTimeout),
    action: action,
  );
}

Future<http.Response> _send(
  Future<http.Response> Function() request, {
  String? action,
}) async {
  final prefix = action == null ? '' : '$action: ';
  try {
    final response = await request();
    if (response.statusCode >= 400) {
      throw AppException(
        '$prefixсервер ответил ошибкой ${response.statusCode} '
        '(${_reasonPhrase(response.statusCode)}).',
        kind: AppErrorKind.server,
      );
    }
    return response;
  } on AppException {
    rethrow;
  } catch (error) {
    throw AppException.from(error, action: action);
  }
}

String _reasonPhrase(int statusCode) {
  if (statusCode == 404) return 'страница не найдена';
  if (statusCode == 403) return 'доступ запрещён';
  if (statusCode >= 500) return 'ошибка на сервере';
  return 'запрос отклонён';
}
