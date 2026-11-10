import 'package:flutter/material.dart';

import 'search_picker_dialog.dart';

/// Боковое меню расписания: выбор курса и одной группы.
///
/// Группа выбирается тем же диалогом с поиском, что и на экране рейтинга.
class CourseDrawer extends StatelessWidget {
  final String selectedCourse;
  final List<String> courses;
  final ValueChanged<String> onSelected;

  /// Все группы факультета (со всех курсов). Пустой список — выбор недоступен.
  final List<String> groups;

  /// Идёт построение списка групп по файлу факультета.
  final bool groupsLoading;

  /// Курс каждой группы — показывается в диалоге рядом с названием.
  final Map<String, String>? groupCourses;

  /// Выбранная группа; null — показываются все группы.
  final String? selectedGroup;
  final ValueChanged<String?> onGroupSelected;

  const CourseDrawer({
    super.key,
    required this.selectedCourse,
    required this.courses,
    required this.onSelected,
    this.groups = const <String>[],
    this.groupsLoading = false,
    this.groupCourses,
    this.selectedGroup,
    required this.onGroupSelected,
  });

  /// Пункт диалога, означающий «показать все группы».
  static const String allGroupsLabel = 'Все группы';

  Future<void> _pickGroup(BuildContext context) async {
    if (groups.isEmpty) return;
    final chosen = await showSearchPickerDialog<String>(
      context: context,
      title: 'Выберите группу',
      items: <String>[allGroupsLabel, ...groups],
      hint: 'Поиск группы',
      labelBuilder: (item) {
        if (item == allGroupsLabel) return item;
        final course = groupCourses?[item];
        return course == null ? item : '$item · $course';
      },
    );
    if (chosen == null) return;
    onGroupSelected(chosen == allGroupsLabel ? null : chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Выбор курса', style: theme.textTheme.titleLarge),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final course = courses[index];
                  final selected = course == selectedCourse;
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                    title: Text(course),
                    selected: selected,
                    onTap: () => onSelected(course),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Группа', style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.group),
                label: Text(
                  groupsLoading
                      ? 'Загружаем группы…'
                      : (selectedGroup ?? allGroupsLabel),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: groupsLoading || groups.isEmpty
                    ? null
                    : () => _pickGroup(context),
              ),
            ),
            if (groupsLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                groupsLoading
                    ? 'Собираем список групп факультета…'
                    : groups.isEmpty
                    ? 'Выберите курс, затем группу'
                    : 'Все группы факультета. Выбор оставляет в таблице '
                          'одну колонку и переключает на нужный курс',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
