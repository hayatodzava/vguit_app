import 'package:flutter/material.dart';

import '../services/net.dart';

/// Показывает окно с понятной причиной ошибки.
///
/// Пользователь видит, что именно случилось и что делать; технические
/// подробности спрятаны под «Подробностями».
Future<void> showErrorDialog(
  BuildContext context, {
  required String title,
  required Object error,
  VoidCallback? onRetry,
}) async {
  if (!context.mounted) return;
  final exception = AppException.from(error);
  final details = exception.details;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Icon(_iconFor(exception.kind), color: scheme.error, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exception.message),
              if (details != null) ...[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(dialogContext)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text(
                      'Подробности',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      SelectableText(
                        details,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
          if (onRetry != null)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onRetry();
              },
              child: const Text('Повторить'),
            ),
        ],
      );
    },
  );
}

/// Короткая ошибка в виде плашки (для некритичных случаев).
void showErrorSnackBar(BuildContext context, String title, Object error) {
  if (!context.mounted) return;
  final exception = AppException.from(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$title: ${exception.message}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Нейтральное сообщение в плашке (не ошибка).
void showMessageSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

IconData _iconFor(AppErrorKind kind) {
  switch (kind) {
    case AppErrorKind.network:
      return Icons.wifi_off_outlined;
    case AppErrorKind.timeout:
      return Icons.hourglass_disabled_outlined;
    case AppErrorKind.server:
      return Icons.cloud_off_outlined;
    case AppErrorKind.parse:
      return Icons.file_present_outlined;
    case AppErrorKind.cache:
      return Icons.sd_storage_outlined;
    case AppErrorKind.unknown:
      return Icons.error_outline;
  }
}
