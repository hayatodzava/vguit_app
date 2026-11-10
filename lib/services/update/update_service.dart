import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/update_info.dart';
import '../net.dart';
import 'update_config.dart';
import 'updater_platform.dart';

/// Поиск обновлений на GitHub и скачивание APK.
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

  /// Скачивает APK во внутренний кэш приложения.
  ///
  /// [onProgress] получает долю от 0 до 1, [isCancelled] прерывает загрузку.
  Future<File> download(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dirPath = await _platform.apkCacheDir();
    if (dirPath == null || dirPath.isEmpty) {
      throw AppException('Не удалось получить каталог для загрузки.');
    }
    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    // Старые файлы обновлений больше не нужны.
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // Не критично, если не удалилось.
          }
        }
      }
    }

    final safeName = info.assetName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safeName');

    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await client.send(request).timeout(kDownloadTimeout);
      if (response.statusCode != 200) {
        throw AppException(
          'Не удалось скачать файл (код ${response.statusCode}).',
          kind: AppErrorKind.server,
        );
      }

      final total = response.contentLength ?? info.sizeBytes ?? 0;
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) break;
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (isCancelled?.call() ?? false) {
        try {
          await file.delete();
        } catch (_) {}
        throw AppException('Загрузка отменена.');
      }
      if (received == 0) {
        throw AppException('Файл обновления скачался пустым.');
      }
      return file;
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException.from(error, action: 'Загрузка обновления');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
    }
  }

  Future<bool> canInstall() => _platform.canInstall();

  Future<void> openInstallSettings() => _platform.openInstallSettings();

  Future<bool> install(File file) => _platform.install(file.path);
}
