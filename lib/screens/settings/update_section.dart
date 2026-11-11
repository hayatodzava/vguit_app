import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/update_info.dart';
import '../../services/net.dart';
import '../../services/update/update_config.dart';
import '../../services/update/update_service.dart';
import '../../widgets/error_dialog.dart';

/// Проверка обновлений и переход к скачиванию.
///
/// Приложение только сообщает о новой версии и открывает ссылку на APK
/// в браузере — установку выполняет система. Поэтому разрешение
/// `REQUEST_INSTALL_PACKAGES` не нужно, и Play Protect не предупреждает.
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
                      ? 'Скачать обновление в браузере?'
                      : 'Скачать обновление в браузере? Размер: $size.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Файл скачается в «Загрузки». Откройте его и нажмите '
                  '«Установить» — Android сам обновит приложение.',
                  style: Theme.of(context).textTheme.bodySmall,
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
            child: const Text('Скачать'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await _openDownload(context, info);
  }

  static Future<void> _openDownload(
    BuildContext context,
    UpdateInfo info,
  ) async {
    var opened = await _service.openDownload(info);
    if (!opened) {
      // Прямая ссылка на файл не открылась — покажем страницу релиза.
      opened = await _service.openReleasePage(info);
    }
    if (!context.mounted) return;

    if (!opened) {
      showErrorDialog(
        context,
        title: 'Не удалось открыть браузер',
        error: AppException(
          'Откройте страницу релиза вручную: ${info.pageUrl}',
        ),
      );
      return;
    }

    showMessageSnackBar(
      context,
      'Файл скачивается в «Загрузки». Откройте его и нажмите «Установить».',
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
        subtitle: Text('Обновления доступны только на Android'),
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
