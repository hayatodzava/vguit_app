/// Сведения о новой версии из GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
    required this.assetName,
    this.sizeBytes,
  });

  /// Версия без префикса «v», например «1.2.0».
  final String version;

  /// Описание релиза (может быть пустым).
  final String notes;

  /// Прямая ссылка на APK-файл.
  final String apkUrl;

  /// Страница релиза — запасной вариант, если APK не скачался.
  final String pageUrl;

  final String assetName;

  /// Размер файла в байтах, если GitHub его сообщил.
  final int? sizeBytes;

  String get sizeLabel {
    final size = sizeBytes;
    if (size == null || size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} МБ';
  }

  @override
  String toString() => 'UpdateInfo($version, $assetName)';
}

/// Текущая версия приложения из манифеста.
class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;

  String get label => name.isEmpty ? '$code' : '$name ($code)';
}

/// Сравнение версий вида «1.2.10» и «1.2.9».
///
/// Возвращает true, если [remote] новее [current]. Сравнение числовое
/// по сегментам, поэтому 1.0.10 > 1.0.9 (строковое сравнение тут врёт).
bool isNewerVersion(String remote, String current) {
  final left = _segments(remote);
  final right = _segments(current);
  if (left.isEmpty || right.isEmpty) return false;

  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final a = i < left.length ? left[i] : 0;
    final b = i < right.length ? right[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

List<int> _segments(String version) {
  final cleaned = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  // Отбрасываем хвост вроде «-beta.1» или «+5».
  final core = cleaned.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  final result = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), ''));
    if (number == null) return const <int>[];
    result.add(number);
  }
  return result;
}
