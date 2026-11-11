import 'package:flutter/services.dart';

import '../../models/update_info.dart';

/// Мост к Android-части: версия приложения и открытие ссылки в браузере.
///
/// Установку APK выполняет система — приложение не запрашивает разрешение
/// на установку, поэтому Play Protect не предупреждает.
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

  /// Открывает ссылку во внешнем браузере. false — открыть не удалось.
  Future<bool> openUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
}
