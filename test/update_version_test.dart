import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/update_info.dart';

void main() {
  group('сравнение версий', () {
    test('новая версия определяется по числу, а не по строке', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
    });

    test('та же версия не считается обновлением', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0'), isFalse);
    });

    test('старая версия не предлагается к установке', () {
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(isNewerVersion('1.2.0', '1.10.0'), isFalse);
    });

    test('префикс v и суффиксы не мешают', () {
      expect(isNewerVersion('v1.2.0', '1.1.9'), isTrue);
      expect(isNewerVersion('V2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.2.0-beta.1', '1.1.0'), isTrue);
      expect(isNewerVersion('1.2.0+7', '1.2.0'), isFalse);
    });

    test('мусор в версии не ломает проверку', () {
      expect(isNewerVersion('', '1.0.0'), isFalse);
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', ''), isFalse);
    });
  });

  test('размер обновления показывается в мегабайтах', () {
    const info = UpdateInfo(
      version: '1.1.0',
      notes: '',
      apkUrl: 'https://example.com/app.apk',
      pageUrl: 'https://example.com',
      assetName: 'app.apk',
      sizeBytes: 12 * 1024 * 1024,
    );
    expect(info.sizeLabel, '12.0 МБ');

    const withoutSize = UpdateInfo(
      version: '1.1.0',
      notes: '',
      apkUrl: 'https://example.com/app.apk',
      pageUrl: 'https://example.com',
      assetName: 'app.apk',
    );
    expect(withoutSize.sizeLabel, isEmpty);
  });
}
