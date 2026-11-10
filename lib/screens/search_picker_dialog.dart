import 'package:flutter/material.dart';

Future<T?> showSearchPickerDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String hint,
  String Function(T item)? labelBuilder,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => _SearchPickerDialog<T>(
      title: title,
      items: items,
      hint: hint,
      labelBuilder: labelBuilder ?? (item) => item.toString(),
    ),
  );
}

class _SearchPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String hint;
  final String Function(T) labelBuilder;

  const _SearchPickerDialog({
    required this.title,
    required this.items,
    required this.hint,
    required this.labelBuilder,
  });

  @override
  State<_SearchPickerDialog<T>> createState() => _SearchPickerDialogState<T>();
}

class _SearchPickerDialogState<T> extends State<_SearchPickerDialog<T>> {
  late TextEditingController _controller;
  late List<T> _filtered;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyFilter(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.items;
        return;
      }
      final matching = widget.items
          .where((it) => widget.labelBuilder(it).toLowerCase().contains(query))
          .toList();
      _filtered = _sortByRelevance(matching, query);
    });
  }

  /// Сортирует: сначала точные совпадения, потом «начинается с», потом «содержит».
  /// Внутри каждой группы — короткие метки первыми.
  List<T> _sortByRelevance(List<T> items, String query) {
    final exact = <T>[];
    final starts = <T>[];
    final contains = <T>[];

    for (final it in items) {
      final label = widget.labelBuilder(it).toLowerCase();
      if (label == query) {
        exact.add(it);
      } else if (label.startsWith(query)) {
        starts.add(it);
      } else {
        contains.add(it);
      }
    }

    int byLen(T a, T b) =>
        widget.labelBuilder(a).length.compareTo(widget.labelBuilder(b).length);

    exact.sort(byLen);
    starts.sort(byLen);
    contains.sort(byLen);

    return [...exact, ...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _applyFilter,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('Ничего не найдено'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final item = _filtered[i];
                        return ListTile(
                          title: Text(widget.labelBuilder(item)),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
