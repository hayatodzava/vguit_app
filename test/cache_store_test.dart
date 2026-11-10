import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vguit_app/services/cache/cache_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('байты сохраняются и читаются без потерь', () async {
    const store = CacheStore(CacheSection.studentsSchedule);
    final bytes = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));

    await store.writeBytes('file', bytes);
    final restored = await store.readBytes('file');

    expect(restored, isNotNull);
    expect(restored, equals(bytes));
  });

  test('вес раздела считается по сохранённым данным', () async {
    const store = CacheStore(CacheSection.studentsSchedule);
    await store.writeBytes('file', Uint8List(2048));

    expect(await store.sizeBytes(), greaterThan(2000));
  });

  test('очистка одного раздела не задевает другие', () async {
    const students = CacheStore(CacheSection.studentsSchedule);
    const rating = CacheStore(CacheSection.rating);
    const teachers = CacheStore(CacheSection.teachersSchedule);

    await students.writeBytes('file', Uint8List(512));
    await rating.writeJson('faculties', <Map<String, String>>[
      {'id': '1', 'name': 'УИТС'},
    ]);
    await teachers.writeJson('list', <String>['Иванов И.И.']);

    await CacheManager().clear(<CacheSection>[CacheSection.rating]);

    expect(await rating.sizeBytes(), 0);
    expect(await students.sizeBytes(), greaterThan(0));
    expect(await teachers.sizeBytes(), greaterThan(0));
  });

  test('метка времени обновления читается обратно', () async {
    const store = CacheStore(CacheSection.teachersSchedule);
    final now = DateTime(2026, 11, 7, 14, 30);

    await store.writeTimestamp('schedule', now);
    final restored = await store.readTimestamp('schedule');

    expect(restored, now);
  });

  test('повреждённый кэш даёт понятную ошибку, а не падение', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${CacheSection.rating.prefix}broken': '{не json',
    });
    const store = CacheStore(CacheSection.rating);

    expect(() => store.readJson('broken'), throwsA(isA<Exception>()));
  });

  test('размер форматируется по-человечески', () {
    expect(formatBytes(0), '0 Б');
    expect(formatBytes(512), '512 Б');
    expect(formatBytes(2048), '2 КБ');
    expect(formatBytes(3 * 1024 * 1024), '3.0 МБ');
  });
}
