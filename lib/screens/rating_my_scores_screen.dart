import 'package:flutter/material.dart';

import '../models/rating.dart';
import '../services/rating_service.dart';
import '../widgets/error_dialog.dart';
import 'rating_vedomost_screen.dart';

class RatingMyScoresScreen extends StatefulWidget {
  final RatingService service;
  final List<Subject> subjects;
  final String recordBook;
  final String groupName;

  const RatingMyScoresScreen({
    super.key,
    required this.service,
    required this.subjects,
    required this.recordBook,
    required this.groupName,
  });

  @override
  State<RatingMyScoresScreen> createState() => _RatingMyScoresScreenState();
}

class _RatingMyScoresScreenState extends State<RatingMyScoresScreen> {
  /// Сколько ведомостей качаем одновременно.
  static const int _parallelism = 4;

  List<MyScore> _scores = const <MyScore>[];
  int _loaded = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll({bool forceServer = false}) async {
    final subjects = widget.subjects;
    setState(() {
      _loading = true;
      _scores = const <MyScore>[];
      _loaded = 0;
    });

    final results = List<MyScore?>.filled(subjects.length, null);
    final failures = <Object>[];
    var nextIndex = 0;
    var completed = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        if (index >= subjects.length) return;
        nextIndex = index + 1;

        final subject = subjects[index];
        try {
          final vedomost = await _fetch(subject, forceServer);
          final row = vedomost.students.firstWhere(
            (student) => student.recordBook == widget.recordBook,
            orElse: () => const StudentRow(
              number: 0,
              recordBook: '',
              scores: <String>[],
              ktTotals: <String>[],
              finalRating: '',
              grade: '',
            ),
          );
          if (row.recordBook.isNotEmpty) {
            results[index] = MyScore(
              subject: subject,
              totalRating: row.finalRating,
              grade: row.grade,
              ktTotals: row.ktTotals,
            );
          }
        } catch (error) {
          failures.add(error);
        }

        completed++;
        if (!mounted) return;
        setState(() {
          _scores = results.whereType<MyScore>().toList(growable: false);
          _loaded = completed;
        });
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < _parallelism; i++) worker(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);

    if (failures.isNotEmpty) {
      showErrorDialog(
        context,
        title: failures.length == 1
            ? 'Не удалось загрузить ведомость'
            : 'Не удалось загрузить часть ведомостей '
                  '(${failures.length} из ${subjects.length})',
        error: failures.first,
        onRetry: () => _loadAll(forceServer: forceServer),
      );
    }
  }

  Future<Vedomost> _fetch(Subject subject, bool forceServer) async {
    if (!forceServer) {
      final cached = await widget.service.loadVedomostFromCache(subject.id);
      if (cached != null) return cached.data;
    }
    final fresh = await widget.service.fetchVedomost(subject.id);
    await widget.service.saveVedomostToCache(fresh);
    return fresh;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Зачётка ${widget.recordBook}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loading ? null : () => _loadAll(forceServer: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Группа: ${widget.groupName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Зачётка: ${widget.recordBook}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: widget.subjects.isEmpty
                      ? 0
                      : _loaded / widget.subjects.length,
                ),
                Text(
                  'Загружено $_loaded из ${widget.subjects.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_scores.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_scores.isEmpty) {
      return const Center(
        child: Text(
          'Не найдено оценок для этой зачётки',
          style: TextStyle(fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      itemCount: _scores.length,
      itemBuilder: (context, index) {
        final score = _scores[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RatingVedomostScreen(
                    service: widget.service,
                    subject: score.subject,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    score.subject.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    score.subject.type,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (score.ktTotals.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (int kt = 0; kt < score.ktTotals.length; kt++)
                          Chip(
                            label: Text(
                              'КТ${kt + 1}: '
                              '${score.ktTotals[kt].isEmpty ? "—" : score.ktTotals[kt]}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Рейтинг: '
                          '${score.totalRating.isEmpty ? "—" : score.totalRating}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        score.grade.isEmpty ? '—' : score.grade,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _gradeColor(score.grade),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color? _gradeColor(String grade) {
    final g = grade.toLowerCase();
    if (g.contains('отл')) return Colors.green;
    if (g.contains('хор')) return Colors.blue;
    if (g.contains('удовл')) return Colors.orange;
    if (g.contains('неуд') || g.contains('н/я')) return Colors.red;
    return null;
  }
}
