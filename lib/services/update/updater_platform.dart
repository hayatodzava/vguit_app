import 'package:flutter/services.dart';

import '../../models/update_info.dart';

/// Мост к Android-части: версия приложения, установка APK, перезапуск.
///
/// Тихая установка обычному приложению недоступна — система показывает
/// своё подтверждение. Наша задача — избавить от поиска файла в проводнике.
class UpdaterPlatform {
  const UpdaterPlatform();

  static const MethodChannel _channel = MethodChannel('vguit_app/updater');

  Future<AppVersion> appVersion() async {
    final info = await _channel.invokeMapMethod<String, Object?>('appInfo');
    return AppVersion(
      name: info?['versionName'] as String? ?? '',
      code: (info?['versionCode'] as num?)?.toInt() ?? 0,
    );
  }

  /// Разрешена ли установка из этого приложения (Android 8+).
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  /// Открыть системный экран «Установка неизвестных приложений».
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  /// Каталог в кэше приложения, откуда FileProvider отдаст APK.
  Future<String?> apkCacheDir() => _channel.invokeMethod<String>('apkCacheDir');

  /// Запустить системный установщик для скачанного файла.
  Future<bool> install(String path) async =>
      await _channel.invokeMethod<bool>('install', {'path': path}) ?? false;

  /// Перезапустить приложение (после установки).
  Future<bool> restart() async =>
      await _channel.invokeMethod<bool>('restart') ?? false;
}
