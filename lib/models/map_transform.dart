import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Взаимно-обратное преобразование «координаты плана ↔ координаты экрана».
///
/// План этажа рисуется «как есть» в координатах JSON (пиксели SVG) и
/// вписывается в вьюпорт коэффициентом [fitScale]; сверху пользователь
/// применяет свой зум [scale], поворот [rotation] и сдвиг [offset].
///
/// Единственный источник истины для отрисовки оверлеев (маршрут, метки)
/// и для попадания жеста «зум под пальцем».
@immutable
class MapTransform {
  const MapTransform({
    required this.viewportSize,
    required this.imageSize,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offset = Offset.zero,
  });

  /// Минимальный/максимальный масштаб относительно вписанного плана.
  static const double minScale = 0.5;
  static const double maxScale = 8.0;

  final Size viewportSize;
  final Size imageSize;

  /// Пользовательский зум (1.0 = план вписан целиком).
  final double scale;
  final double rotation;

  /// Сдвиг в экранных пикселях.
  final Offset offset;

  /// Коэффициент вписывания плана в вьюпорт.
  double get fitScale {
    final imageWidth = imageSize.width > 0 ? imageSize.width : 1.0;
    final imageHeight = imageSize.height > 0 ? imageSize.height : 1.0;
    final viewportWidth = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final viewportHeight = viewportSize.height > 0 ? viewportSize.height : 1.0;
    return math.min(viewportWidth / imageWidth, viewportHeight / imageHeight);
  }

  /// Итоговый масштаб: план → экран.
  double get total => fitScale * scale;

  Offset get imageCenter => Offset(imageSize.width / 2, imageSize.height / 2);

  Offset get screenCenter =>
      Offset(viewportSize.width / 2, viewportSize.height / 2);

  /// Координаты плана → экран.
  Offset toScreen(Offset mapPoint) {
    final relative = (mapPoint - imageCenter) * total;
    return _rotate(relative, rotation) + screenCenter + offset;
  }

  /// Экран → координаты плана.
  Offset toMap(Offset screenPoint) {
    final relative = (screenPoint - screenCenter - offset) / total;
    return _rotate(relative, -rotation) + imageCenter;
  }

  MapTransform copyWith({double? scale, double? rotation, Offset? offset}) {
    return MapTransform(
      viewportSize: viewportSize,
      imageSize: imageSize,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      offset: offset ?? this.offset,
    );
  }

  /// Вернуть трансформацию, при которой [mapPoint] окажется под [screenPoint].
  ///
  /// Используется для жеста зума: точка плана, которую захватили пальцы,
  /// должна остаться под ними при новом масштабе/повороте.
  MapTransform anchor({required Offset mapPoint, required Offset screenPoint}) {
    final relative = _rotate((mapPoint - imageCenter) * total, rotation);
    return copyWith(offset: screenPoint - screenCenter - relative);
  }

  /// Зум в [factor] раз относительно центра экрана.
  MapTransform zoomedBy(double factor) {
    final nextScale = (scale * factor).clamp(minScale, maxScale).toDouble();
    return copyWith(scale: nextScale)
        .anchor(mapPoint: toMap(screenCenter), screenPoint: screenCenter);
  }

  /// Исходный вид: план вписан целиком, без поворота и сдвига.
  MapTransform get reset =>
      MapTransform(viewportSize: viewportSize, imageSize: imageSize);

  /// Матрица для [Transform] с `alignment: Alignment.center`.
  ///
  /// Повторяет [toScreen]: сдвиг, поворот и масштаб вокруг центра плана.
  Matrix4 toMatrix() => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    ..rotateZ(rotation)
    ..scaleByDouble(total, total, 1, 1);

  bool get isDefault => scale == 1.0 && rotation == 0 && offset == Offset.zero;

  static Offset _rotate(Offset vector, double angle) {
    if (angle == 0) return vector;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(
      vector.dx * cos - vector.dy * sin,
      vector.dx * sin + vector.dy * cos,
    );
  }
}
