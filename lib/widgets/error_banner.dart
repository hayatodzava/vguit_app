import 'package:flutter/material.dart';

import '../services/net.dart';

/// Плашка с причиной ошибки и кнопкой повтора.
///
/// Используется, когда данные уже показаны и падение не должно прятать
/// экран целиком (например, не обновилось расписание, но старое есть).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.error,
    this.onRetry,
    this.retryLabel = 'Повторить',
  });

  final AppException error;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.message,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}
