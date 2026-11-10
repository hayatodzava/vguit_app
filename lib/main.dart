import 'dart:async';

import 'package:flutter/material.dart';

import 'services/notifications/notification_store.dart';
import 'services/notifications/schedule_alarm_scheduler.dart';
import 'services/notifications/schedule_notifier.dart';
import 'screens/settings/update_section.dart';
import 'theme_controller.dart';
import 'screens/schedule_screen.dart';
import 'screens/rating_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_prepareBackgroundChecks());
  runApp(const MyApp());
}

/// Готовит уведомления и восстанавливает цепочку будильников.
///
/// Если будильник не сработал (телефон был выключен, приложение обновляли),
/// следующая проверка ставится заново при запуске приложения.
Future<void> _prepareBackgroundChecks() async {
  try {
    await ScheduleNotifier.instance.initialize();
    const store = NotificationStore();
    final settings = await store.loadSettings();
    await const ScheduleAlarmScheduler().apply(settings);
  } catch (error) {
    debugPrint('[startup] фоновые проверки недоступны: $error');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeController _themeController = ThemeController();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'ВГУИТ Студент',
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: HomePage(themeController: _themeController),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  final ThemeController themeController;
  const HomePage({super.key, required this.themeController});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Молча проверяем обновления после первого кадра: диалог появится,
    // только если на GitHub есть версия новее установленной.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateFlow.check(context, silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ScheduleScreen(),
      const RatingScreen(),
      const MapScreen(),
      SettingsScreen(themeController: widget.themeController),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Расписание',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Рейтинг',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Карта',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
