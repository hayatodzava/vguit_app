import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/update_info.dart';
import '../net.dart';
import 'update_config.dart';
import 'updater_platform.dart';

/// Поиск обновлений на GitHub.
///
/// Приложение только сообщает о новой версии и открывает ссылку на APK
/// в браузере: установку выполняет система. Так не требуется разрешение
/// `REQUEST_INSTALL_PACKAGES`, из-за которого Play Protect предупреждал.
class UpdateService {
  const UpdateService();

  static const UpdaterPlatform _platform = UpdaterPlatform();

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'vguit-app-updater',
  };

  /// Текущая установленная версия.
  Future<AppVersion> currentVersion() => _platform.appVersion();

  /// Открывает страницу загрузки APK в браузере.
  Future<bool> openDownload(UpdateInfo info) => _platform.openUrl(info.apkUrl);

  /// Открывает страницу релиза (запасной вариант).
  Future<bool> openReleasePage(UpdateInfo info) =>
      _platform.openUrl(info.pageUrl);

  /// Последний релиз, если он новее установленного. Иначе null.
  Future<UpdateInfo?> check() async {
    if (!isUpdateConfigured) return null;

    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(latestReleaseApiUrl), headers: _headers)
          .timeout(kRequestTimeout);
    } catch (error) {
      throw AppException.from(error, action: 'Проверка обновлений');
    }

    // 404 — релизов ещё нет, обновляться не с чего.
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403) {
      throw AppException(
        'GitHub временно ограничил запросы. Попробуйте позже.',
        kind: AppErrorKind.server,
      );
    }
    if (response.statusCode != 200) {
      throw AppException(
        'GitHub ответил ошибкой ${response.statusCode}.',
        kind: AppErrorKind.server,
      );
    }

    final Map<String, dynamic> release;
    try {
      release = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      throw AppException.parse(
        'Не удалось разобрать ответ GitHub.',
        cause: error,
      );
    }

    final tag = (release['tag_name'] as String?)?.trim() ?? '';
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (version.isEmpty) return null;

    final current = await currentVersion();
    if (!isNewerVersion(version, current.name)) return null;

    final assets = (release['assets'] as List?) ?? const <Object?>[];
    Map<String, dynamic>? apk;
    for (final item in assets) {
      if (item is! Map) continue;
      final name = (item['name'] as String?)?.toLowerCase() ?? '';
      if (!name.endsWith('.apk')) continue;
      apk = item.cast<String, dynamic>();
      break;
    }
    if (apk == null) {
      throw AppException(
        'В релизе $version нет APK-файла. Откройте страницу релиза вручную.',
        kind: AppErrorKind.parse,
      );
    }

    return UpdateInfo(
      version: version,
      notes: (release['body'] as String?)?.trim() ?? '',
      apkUrl: apk['browser_download_url'] as String,
      pageUrl: (release['html_url'] as String?) ?? releasesPageUrl,
      assetName: (apk['name'] as String?) ?? 'update.apk',
      sizeBytes: (apk['size'] as num?)?.toInt(),
    );
  }
}
