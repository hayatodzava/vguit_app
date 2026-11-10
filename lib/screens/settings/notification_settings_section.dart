import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/schedule_notification_settings.dart';
import '../../services/notifications/schedule_notifier.dart';
import '../../services/notifications/schedule_watcher.dart';
import '../../services/schedule_cache.dart';
import '../../services/schedule_sources.dart';
import '../../widgets/error_dialog.dart';

/// Раздел «Уведомления» в настройках.
///
/// Показывает чекбокс, а при включении — расписание проверок, факультет
/// и группы. Все изменения сразу уходят в [onChanged]: экран настроек
/// сохраняет их и перепланирует будильник.
class NotificationSettingsSection extends StatefulWidget {
  const NotificationSettingsSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ScheduleNotificationSettings settings;
  final ValueChanged<ScheduleNotificationSettings> onChanged;

  @override
  State<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends State<NotificationSettingsSection> {
  List<String>? _groups;
  bool _loadingGroups = false;
  bool _checking = false;

  ScheduleNotificationSettings get _settings => widget.settings;

  void _update(ScheduleNotificationSettings next) => widget.onChanged(next);

  // ─── Действия ───

  Future<void> _toggle(bool enabled) async {
    if (enabled) {
      final notifier = ScheduleNotifier.instance;
      final granted = await notifier.requestPermission();
      if (!mounted) return;
      if (!granted) {
        showMessageSnackBar(
          context,
          'Уведомления запрещены. Разрешите их в настройках телефона, '
          'иначе сообщения об изменениях не придут.',
        );
      }

      // Точный будильник на Android 12+ требует отдельного разрешения.
      if (defaultTargetPlatform == TargetPlatform.android) {
        final exact = await notifier.canScheduleExactAlarms();
        if (!exact) {
          await notifier.requestExactAlarmPermission();
          if (!mounted) return;
          showMessageSnackBar(
            context,
            'Без разрешения «Будильники и напоминания» проверка может '
            'запускаться с задержкой в несколько минут.',
          );
        }
      }
    }
    _update(_settings.copyWith(enabled: enabled));
  }

  Future<void> _pickFaculty(String? faculty) async {
    if (faculty == null || faculty == _settings.faculty) return;
    setState(() => _groups = null);
    _update(_settings.copyWith(faculty: faculty, groups: const <String>[]));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
    );
    if (picked == null) return;
    _update(_settings.copyWith(hour: picked.hour, minute: picked.minute));
  }

  /// Загружает список групп факультета (из кэша или с сайта).
  Future<List<String>> _ensureGroups() async {
    final cached = _groups;
    if (cached != null) return cached;

    final faculty = _settings.faculty;
    if (faculty == null) return const <String>[];

    setState(() {
      _loadingGroups = true;
    });
    try {
      const cache = ScheduleCache();
      var bytes = await cache.loadBytes(faculty);
      bytes ??= await ScheduleSources.download(
        faculty,
        action: 'Загрузка списка групп',
      );
      final groups = await compute(ScheduleSources.groupNames, bytes);
      if (mounted) setState(() => _groups = groups);
      return groups;
    } catch (error) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Не удалось получить список групп',
          error: error,
        );
      }
      return const <String>[];
    } finally {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _pickGroups() async {
    final available = await _ensureGroups();
    if (!mounted || available.isEmpty) {
      if (mounted && !_loadingGroups) {
        showMessageSnackBar(
          context,
          'Не удалось получить список групп факультета. Попробуйте позже.',
        );
      }
      return;
    }

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _GroupPickerDialog(
        title: 'Группы для отслеживания',
        groups: available,
        initial: _settings.groups,
      ),
    );
    if (!mounted || selected == null) return;
    final ordered = available.where(selected.contains).toList(growable: false);
    _update(_settings.copyWith(groups: ordered));
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final result = await const ScheduleWatcher().run(_settings);
      if (!mounted) return;

      if (result.hasChanges) {
        await ScheduleNotifier.instance.showScheduleChanged(
          faculty: _settings.faculty!,
          groups: result.changedGroups,
          changes: result.changes,
        );
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.notifications_active_outlined),
            title: const Text('Расписание изменилось'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in result.changedGroups)
                    Text('$group: ${result.changes[group]?.join('; ')}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        );
      } else {
        showMessageSnackBar(
          context,
          'Изменений нет. Кэш расписания обновлён в '
          '${_formatTime(result.checkedAt)}.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      showErrorDialog(context, title: 'Проверка не удалась', error: error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _settings.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: _toggle,
          title: const Text('Изменения расписания студентов'),
          subtitle: const Text(
            'Проверять расписание в выбранное время и присылать уведомление',
          ),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ScheduleCheckFrequency>(
                  initialValue: _settings.frequency,
                  key: ValueKey('freq-${_settings.frequency.name}'),
                  decoration: const InputDecoration(
                    labelText: 'Как часто проверять',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ScheduleCheckFrequency.values
                      .map(
                        (frequency) => DropdownMenuItem(
                          value: frequency,
                          child: Text(frequency.label),
                        ),
                      )
                      .toList(),
                  onChanged: (frequency) {
                    if (frequency == null) return;
                    _update(_settings.copyWith(frequency: frequency));
                  },
                ),
                if (_settings.frequency == ScheduleCheckFrequency.weekly) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _settings.weekday,
                    key: ValueKey('weekday-${_settings.weekday}'),
                    decoration: const InputDecoration(
                      labelText: 'День недели',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List<DropdownMenuItem<int>>.generate(
                      7,
                      (index) => DropdownMenuItem<int>(
                        value: index + 1,
                        child: Text(
                          ScheduleNotificationSettings.weekdayName(index + 1),
                        ),
                      ),
                    ),
                    onChanged: (weekday) {
                      if (weekday == null) return;
                      _update(_settings.copyWith(weekday: weekday));
                    },
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Время проверки'),
                  subtitle: Text(_settings.timeLabel),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _pickTime,
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: _settings.faculty,
                  key: ValueKey(
                    'notify-faculty-${_settings.faculty ?? 'none'}',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Факультет',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ScheduleSources.faculties
                      .map(
                        (faculty) => DropdownMenuItem(
                          value: faculty,
                          child: Text(faculty),
                        ),
                      )
                      .toList(),
                  onChanged: _pickFaculty,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _loadingGroups
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.groups_outlined),
                  title: const Text('Группы'),
                  subtitle: Text(
                    _settings.groups.isEmpty
                        ? 'Не выбраны'
                        : _settings.groups.join(', '),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _loadingGroups ? null : _pickGroups,
                ),
                const SizedBox(height: 4),
                Text(
                  _settings.faculty == null || _settings.groups.isEmpty
                      ? 'Выберите факультет и хотя бы одну группу'
                      : enabled
                      ? _nextRunLabel()
                      : '',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: !_settings.isComplete || _checking
                          ? null
                          : _checkNow,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _checking ? 'Проверяем…' : 'Проверить сейчас',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  defaultTargetPlatform == TargetPlatform.android
                      ? 'Проверка идёт в фоне по будильнику Android, '
                            'приложение при этом может быть закрыто.'
                      : 'Фоновые проверки доступны только на Android; '
                            'здесь работает кнопка «Проверить сейчас».',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Первая проверка запоминает текущее расписание — '
                  'уведомление придёт только когда оно изменится.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _nextRunLabel() {
    if (!_settings.isComplete) return '';
    final next = _settings.nextRun(DateTime.now());
    return 'Следующая проверка: ${_formatDateTime(next)}';
  }

  static String _formatDateTime(DateTime value) {
    final now = DateTime.now();
    final sameDay =
        value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    final time =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'сегодня в $time';

    final tomorrow = now.add(const Duration(days: 1));
    if (value.year == tomorrow.year &&
        value.month == tomorrow.month &&
        value.day == tomorrow.day) {
      return 'завтра в $time';
    }
    return '${value.day.toString().padLeft(2, '0')}.'
        '${value.month.toString().padLeft(2, '0')} в $time';
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// Выбор нескольких групп с поиском.
class _GroupPickerDialog extends StatefulWidget {
  const _GroupPickerDialog({
    required this.title,
    required this.groups,
    required this.initial,
  });

  final String title;
  final List<String> groups;
  final List<String> initial;

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  late final Set<String> _selected = widget.initial.toSet();
  late List<String> _filtered = widget.groups;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final needle = query.trim().toLowerCase();
    setState(() {
      _filtered = needle.isEmpty
          ? widget.groups
          : widget.groups
                .where((group) => group.toLowerCase().contains(needle))
                .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Поиск группы',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Ничего не найдено'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final group = _filtered[index];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(group),
                          title: Text(group),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selected.add(group);
                              } else {
                                _selected.remove(group);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Text('Выбрать (${_selected.length})'),
        ),
      ],
    );
  }
}
