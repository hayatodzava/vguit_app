import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vguit_app/models/map_transform.dart';

void main() {
  const viewport = Size(1000, 600);
  // Пропорции реального плана: 1797 x 1114.
  const image = Size(1797, 1114);

  test('вписанный план занимает максимально возможную площадь', () {
    const transform = MapTransform(viewportSize: viewport, imageSize: image);
    expect(transform.fitScale, closeTo(600 / 1114, 1e-9));
    expect(transform.total, closeTo(transform.fitScale, 1e-9));
  });

  test('центр плана попадает в центр экрана', () {
    const transform = MapTransform(viewportSize: viewport, imageSize: image);
    final center = Offset(image.width / 2, image.height / 2);
    expect(
      transform.toScreen(center),
      offsetMoreOrLessEquals(viewport.center(Offset.zero)),
    );
  });

  test('экран -> план -> экран возвращает исходную точку', () {
    for (final sample in <MapTransform>[
      const MapTransform(viewportSize: viewport, imageSize: image),
      const MapTransform(
        viewportSize: viewport,
        imageSize: image,
        scale: 2.7,
        rotation: 0.42,
        offset: Offset(-130, 64),
      ),
      const MapTransform(
        viewportSize: viewport,
        imageSize: image,
        scale: 0.5,
        rotation: -1.1,
        offset: Offset(80, -220),
      ),
    ]) {
      for (final point in const <Offset>[
        Offset.zero,
        Offset(1797, 1114),
        Offset(450, 820),
        Offset(1300, 200),
      ]) {
        final screen = sample.toScreen(point);
        final back = sample.toMap(screen);
        expect(back.dx, closeTo(point.dx, 0.001));
        expect(back.dy, closeTo(point.dy, 0.001));
      }
    }
  });

  test('anchor оставляет точку плана под пальцем', () {
    const start = MapTransform(viewportSize: viewport, imageSize: image);
    const finger = Offset(320, 180);
    final mapPoint = start.toMap(finger);

    final next = start
        .copyWith(scale: 3.2, rotation: 0.8)
        .anchor(mapPoint: mapPoint, screenPoint: finger);

    expect(
      next.toScreen(mapPoint),
      offsetMoreOrLessEquals(finger, epsilon: 0.001),
    );
    expect(next.scale, 3.2);
  });

  test('zoomedBy ограничивает масштаб и держит центр', () {
    const start = MapTransform(viewportSize: viewport, imageSize: image);
    final zoomedIn = start.zoomedBy(100);
    expect(zoomedIn.scale, MapTransform.maxScale);

    final zoomedOut = start.zoomedBy(0.001);
    expect(zoomedOut.scale, MapTransform.minScale);

    final center = start.toMap(start.screenCenter);
    expect(
      zoomedIn.toScreen(center),
      offsetMoreOrLessEquals(start.screenCenter, epsilon: 0.001),
    );
  });

  test('reset возвращает исходный вид', () {
    const moved = MapTransform(
      viewportSize: viewport,
      imageSize: image,
      scale: 2,
      rotation: 1,
      offset: Offset(50, 50),
    );
    const fresh = MapTransform(viewportSize: viewport, imageSize: image);
    final reset = moved.reset;
    expect(reset.isDefault, isTrue);
    expect(
      reset.toScreen(const Offset(0, 0)),
      offsetMoreOrLessEquals(fresh.toScreen(const Offset(0, 0))),
    );
  });

  test('нулевой вьюпорт не даёт NaN и бесконечностей', () {
    const transform = MapTransform(viewportSize: Size.zero, imageSize: image);
    expect(transform.fitScale.isFinite, isTrue);
    expect(transform.toScreen(Offset.zero).dx.isFinite, isTrue);
  });
}
