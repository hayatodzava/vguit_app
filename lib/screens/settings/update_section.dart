import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/update_info.dart';
import '../../services/net.dart';
import '../../services/update/update_config.dart';
import '../../services/update/update_service.dart';
import '../../widgets/error_dialog.dart';

/// Проверка обновлений и установка новой версии.
///
/// Вызывается при запуске (молча) и кнопкой в настройках.
class UpdateFlow {
  const UpdateFlow._();

  static const UpdateService _service = UpdateService();

  /// Показывали ли предложение в этом запуске (чтобы не надоедать).
  static bool _offeredThisLaunch = false;

  static Future<void> check(
    BuildContext context, {
    required bool silent,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (!silent) {
        showMessageSnackBar(context, 'Обновления доступны только на Android.');
      }
      return;
    }
    if (!isUpdateConfigured) {
      if (!silent) {
        showMessageSnackBar(
          context,
          'Источник обновлений не настроен: укажите логин и репозиторий '
          'в lib/services/update/update_config.dart.',
        );
      }
      return;
    }

    UpdateInfo? info;
    try {
      info = await _service.check();
    } catch (error) {
      if (!context.mounted) return;
      // На старте молчим: пользователь не просил проверять.
      if (!silent) {
        showErrorDialog(
          context,
          title: 'Не удалось проверить обновления',
          error: error,
        );
      }
      return;
    }

    if (!context.mounted) return;
    if (info == null) {
      if (!silent) showMessageSnackBar(context, 'У вас последняя версия.');
      return;
    }
    if (silent && _offeredThisLaunch) return;
    _offeredThisLaunch = true;

    await _offer(context, info);
  }

  static Future<void> _offer(BuildContext context, UpdateInfo info) async {
    final size = info.sizeLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update, size: 32),
        title: Text('Доступно обновление ${info.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340, maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  size.isEmpty
                      ? 'Скачать и установить сейчас?'
                      : 'Скачать и установить сейчас? Размер: $size.',
                ),
                if (info.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Что нового:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(info.notes),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Скачать и установить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await _install(context, info);
  }

  static Future<void> _install(BuildContext context, UpdateInfo info) async {
    // Android 8+ требует явного разрешения на установку из этого приложения.
    final allowed = await _service.canInstall();
    if (!context.mounted) return;
    if (!allowed) {
      await _showInstallPermissionDialog(context);
      return;
    }

    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(info: info),
    );
    if (!context.mounted) return;

    if (result is File) {
      final launched = await _service.install(result);
      if (!context.mounted) return;
      if (!launched) {
        showErrorDialog(
          context,
          title: 'Не удалось запустить установку',
          error: AppException(
            'Система не открыла установщик. Откройте APK вручную '
            'или разрешите установку из этого приложения.',
          ),
        );
      }
      return;
    }

    if (result is AppException) {
      // Отмену пользователем не показываем как ошибку.
      if (result.message.contains('отменена')) return;
      showErrorDialog(
        context,
        title: 'Не удалось скачать обновление',
        error: result,
      );
      return;
    }
    if (result != null) {
      showErrorDialog(
        context,
        title: 'Не удалось скачать обновление',
        error: result,
      );
    }
  }

  static Future<void> _showInstallPermissionDialog(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.security_outlined, size: 32),
        title: const Text('Разрешите установку'),
        content: const Text(
          'Android требует один раз разрешить установку обновлений '
          'из этого приложения.\n\n'
          'Откройте настройки и включите «Разрешить установку из этого '
          'источника», затем вернитесь и нажмите «Проверить обновление» '
          'ещё раз.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
    if (open == true) {
      await _service.openInstallSettings();
    }
  }
}

/// Окно загрузки: показывает прогресс и возвращает файл или ошибку.
class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  static const UpdateService _service = UpdateService();

  double _progress = 0;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final file = await _service.download(
        widget.info,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context)
          .pop(error is AppException ? error : AppException.from(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).clamp(0, 100).round();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Загрузка ${widget.info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 12),
            Text(
              _progress > 0 ? '$percent%' : 'Подготовка…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _cancelled = true),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }
}

/// Раздел «Обновления» в настройках.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  static const UpdateService _service = UpdateService();

  AppVersion? _version;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await _service.currentVersion();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (_) {
      // Версию не узнать — не критично, покажем прочерк.
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await UpdateFlow.check(context, silent: false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ListTile(
        leading: Icon(Icons.system_update_outlined),
        title: Text('Обновления'),
        subtitle: Text('Автообновление доступно только на Android'),
      );
    }

    final version = _version;
    return ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: const Text('Обновления'),
      subtitle: Text(
        version == null ? 'Проверка версии…' : 'Версия ${version.label}',
      ),
      trailing: _checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: _check, child: const Text('Проверить')),
      onTap: _checking ? null : _check,
    );
  }
}
