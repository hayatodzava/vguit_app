import 'package:flutter/material.dart';

import '../models/schedule_notification_settings.dart';
import '../services/cache/cache_store.dart';
import '../services/notifications/notification_store.dart';
import '../services/notifications/schedule_alarm_scheduler.dart';
import '../theme_controller.dart';
import '../widgets/error_dialog.dart';
import 'settings/notification_settings_section.dart';
import 'settings/update_section.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;
  const SettingsScreen({super.key, required this.themeController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const CacheManager _cacheManager = CacheManager();
  static const NotificationStore _notificationStore = NotificationStore();
  static const ScheduleAlarmScheduler _scheduler = ScheduleAlarmScheduler();

  int? _cacheSize;
  bool _cacheBusy = false;

  ScheduleNotificationSettings _notificationSettings =
      const ScheduleNotificationSettings();

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final settings = await _notificationStore.loadSettings();
      if (!mounted) return;
      setState(() => _notificationSettings = settings);
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось прочитать настройки', error);
    }
  }

  Future<void> _saveNotificationSettings(
    ScheduleNotificationSettings settings,
  ) async {
    setState(() => _notificationSettings = settings);
    try {
      await _notificationStore.saveSettings(settings);
      await _scheduler.apply(settings);
    } catch (error) {
      if (!mounted) return;
      showErrorDialog(
        context,
        title: 'Не удалось сохранить уведомления',
        error: error,
      );
    }
  }

  Future<void> _loadCacheSize() async {
    try {
      final size = await _cacheManager.totalSizeBytes();
      if (!mounted) return;
      setState(() => _cacheSize = size);
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось посчитать кэш', error);
    }
  }

  Future<void> _openCacheDialog() async {
    setState(() => _cacheBusy = true);
    List<CacheEntry> entries;
    try {
      entries = await _cacheManager.inspect();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cacheBusy = false);
      showErrorSnackBar(context, 'Не удалось посчитать кэш', error);
      return;
    }
    if (!mounted) return;
    setState(() => _cacheBusy = false);

    final selected = await showDialog<Set<CacheSection>>(
      context: context,
      builder: (_) => _CacheDialog(entries: entries),
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    try {
      final freed = await _cacheManager.clear(selected);
      if (!mounted) return;
      await _loadCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              freed == 0
                  ? 'Выбранный кэш уже пуст'
                  : 'Кэш очищен: ${formatBytes(freed)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось очистить кэш', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListenableBuilder(
        listenable: widget.themeController,
        builder: (context, _) {
          return ListView(
            children: [
              const _SectionTitle('Оформление'),
              RadioGroup<ThemeMode>(
                groupValue: widget.themeController.themeMode,
                onChanged: (mode) {
                  if (mode != null) widget.themeController.setThemeMode(mode);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('Системная тема'),
                      subtitle: Text('Как в настройках телефона'),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Светлая тема'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Тёмная тема'),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const Divider(),
              const _SectionTitle('Уведомления'),
              NotificationSettingsSection(
                settings: _notificationSettings,
                onChanged: _saveNotificationSettings,
              ),
              const Divider(),
              const _SectionTitle('Данные'),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Очистить кэш'),
                subtitle: Text(
                  _cacheSize == null
                      ? 'Подсчёт размера…'
                      : 'Занято ${formatBytes(_cacheSize!)}',
                ),
                trailing: _cacheBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _cacheBusy ? null : _openCacheDialog,
              ),
              const Divider(),
              const _SectionTitle('О приложении'),
              const UpdateSection(),
              const ListTile(
                leading: Icon(Icons.school_outlined),
                title: Text('ВГУИТ Помощник'),
                subtitle: Text('Карта, расписание и рейтинг ВГУИТ'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Окно выбора разделов кэша: у каждого свой вес.
class _CacheDialog extends StatefulWidget {
  const _CacheDialog({required this.entries});

  final List<CacheEntry> entries;

  @override
  State<_CacheDialog> createState() => _CacheDialogState();
}

class _CacheDialogState extends State<_CacheDialog> {
  late final Set<CacheSection> _selected = <CacheSection>{
    for (final entry in widget.entries)
      if (!entry.isEmpty) entry.section,
  };

  int get _selectedSize => widget.entries
      .where((entry) => _selected.contains(entry.section))
      .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Очистить кэш'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in widget.entries)
                CheckboxListTile(
                  value: _selected.contains(entry.section),
                  onChanged: entry.isEmpty
                      ? null
                      : (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(entry.section);
                            } else {
                              _selected.remove(entry.section);
                            }
                          });
                        },
                  title: Text(entry.title),
                  subtitle: Text('${entry.description}\n${entry.sizeLabel}'),
                  isThreeLine: true,
                  secondary: Icon(
                    entry.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.folder_outlined,
                    color: entry.isEmpty ? scheme.outline : null,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Будет удалено: ${formatBytes(_selectedSize)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty || _selectedSize == 0
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Очистить'),
        ),
      ],
    );
  }
}
