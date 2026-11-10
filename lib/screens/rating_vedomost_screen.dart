import 'package:flutter/material.dart';

import '../models/rating.dart';
import '../services/net.dart';
import '../services/rating_service.dart';
import '../widgets/error_dialog.dart';

class RatingVedomostScreen extends StatefulWidget {
  final RatingService service;
  final Subject subject;

  const RatingVedomostScreen({
    super.key,
    required this.service,
    required this.subject,
  });

  @override
  State<RatingVedomostScreen> createState() => _RatingVedomostScreenState();
}

class _RatingVedomostScreenState extends State<RatingVedomostScreen> {
  Vedomost? _vedomost;
  bool _loading = true;
  AppException? _error;
  bool _forceServer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_forceServer) {
        final cached = await widget.service.loadVedomostFromCache(
          widget.subject.id,
        );
        if (cached != null) {
          if (!mounted) return;
          setState(() {
            _vedomost = cached.data;
            _loading = false;
          });
          return;
        }
      }
      final fresh = await widget.service.fetchVedomost(widget.subject.id);
      await widget.service.saveVedomostToCache(fresh);
      if (!mounted) return;
      setState(() {
        _vedomost = fresh;
        _forceServer = false;
      });
    } catch (error) {
      if (!mounted) return;
      final exception = AppException.from(error);
      setState(() => _error = exception);
      showErrorDialog(
        context,
        title: 'Не удалось загрузить ведомость',
        error: exception,
        onRetry: () {
          _forceServer = true;
          _load();
        },
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Запросить с сервера',
            onPressed: _loading
                ? null
                : () {
                    _forceServer = true;
                    _load();
                  },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _vedomost == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _vedomost == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(_error!.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  _forceServer = true;
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    final vedomost = _vedomost;
    if (vedomost == null) {
      return const Center(child: Text('Нет данных'));
    }
    return _buildContent(vedomost);
  }

  Widget _buildContent(Vedomost v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Группа: ${v.groupName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Преподаватель: ${v.teacher}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Семестр: ${v.semester}, год: ${v.year}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Тип: ${v.type}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildTable(v)),
      ],
    );
  }

  Widget _buildTable(Vedomost v) {
    const double numW = 40;
    const double bookW = 100;
    const double cellW = 55;
    const double ktW = 65;
    const double ratingW = 70;
    const double gradeW = 80;

    final ktCount = v.controlPoints.length;

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 3.0,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _headerCell('№', numW),
              _headerCell('Зачётка', bookW),
              for (int kt = 0; kt < ktCount; kt++) ...[
                _headerCell(v.controlPoints[kt].name, cellW * 4, small: true),
                _headerCell('Итог КТ ${kt + 1}', ktW, small: true),
              ],
              _headerCell('Надбавка', 60, small: true),
              _headerCell('Итоговый\nрейтинг', ratingW, small: true),
              _headerCell('Оценка', gradeW, small: true),
            ],
          ),
          Row(
            children: [
              _subHeaderCell('', numW),
              _subHeaderCell('', bookW),
              for (int kt = 0; kt < ktCount; kt++) ...[
                _subHeaderCell(
                  v.controlPoints[kt].date,
                  cellW * 4,
                  small: true,
                ),
                _subHeaderCell(
                  'вес ${v.controlPoints[kt].weightPercent}%',
                  ktW,
                  small: true,
                ),
              ],
              _subHeaderCell('', 60),
              _subHeaderCell('', ratingW),
              _subHeaderCell('', gradeW),
            ],
          ),
          Row(
            children: [
              _subHeaderCell('', numW),
              _subHeaderCell('', bookW),
              for (int kt = 0; kt < ktCount; kt++) ...[
                _subHeaderCell('Лек', cellW, small: true),
                _subHeaderCell('Пр', cellW, small: true),
                _subHeaderCell('Лаб', cellW, small: true),
                _subHeaderCell('Др', cellW, small: true),
                _subHeaderCell('', ktW),
              ],
              _subHeaderCell('', 60),
              _subHeaderCell('', ratingW),
              _subHeaderCell('', gradeW),
            ],
          ),
          Row(
            children: [
              _subHeaderCell('', numW),
              _subHeaderCell('', bookW),
              for (int kt = 0; kt < ktCount; kt++) ...[
                for (int j = 0; j < 4; j++)
                  _subHeaderCell(
                    '${_weightAt(v.controlPoints[kt], j)}%',
                    cellW,
                    small: true,
                  ),
                _subHeaderCell('', ktW),
              ],
              _subHeaderCell('', 60),
              _subHeaderCell('', ratingW),
              _subHeaderCell('', gradeW),
            ],
          ),
          ...v.students.map((student) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dataCell('${student.number}', numW),
                _dataCell(student.recordBook, bookW),
                for (int kt = 0; kt < ktCount; kt++) ...[
                  for (int j = 0; j < 4; j++)
                    _dataCell(
                      (kt * 4 + j) < student.scores.length
                          ? student.scores[kt * 4 + j]
                          : '',
                      cellW,
                    ),
                  _dataCell(
                    kt < student.ktTotals.length ? student.ktTotals[kt] : '',
                    ktW,
                  ),
                ],
                _dataCell('', 60),
                _dataCell(student.finalRating, ratingW, bold: true),
                _dataCell(student.grade, gradeW, highlight: true),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Вес части КТ с защитой от старого/битого кэша.
  int _weightAt(ControlPoint point, int index) =>
      index < point.weights.length ? point.weights[index] : 0;

  Widget _headerCell(String text, double width, {bool small = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: small ? 11 : 13,
        ),
      ),
    );
  }

  Widget _subHeaderCell(String text, double width, {bool small = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: 0.5),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: small ? 10 : 11),
      ),
    );
  }

  Widget _dataCell(
    String text,
    double width, {
    bool bold = false,
    bool highlight = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: highlight ? _gradeColor(text) : null,
        ),
      ),
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
