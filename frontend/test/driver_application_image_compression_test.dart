import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver_application/config/driver_application_upload_limits.dart';
import 'package:frontend/features/driver_application/models/driver_application_models.dart';
import 'package:frontend/features/driver_application/services/driver_application_image_compression_service.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int width, int height, {int quality = 100}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      image.setPixelRgb(x, y, (x * 7) % 255, (y * 5) % 255, 120);
    }
  }
  return img.encodeJpg(image, quality: quality);
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      image.setPixelRgb(x, y, (x * 9) % 255, (y * 3) % 255, 180);
    }
  }
  return img.encodePng(image, level: 0);
}

void main() {
  const service = DriverApplicationImageCompressionService();

  test('large vehicle JPEG is resized and compressed', () async {
    final source = _jpeg(3200, 2400);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'car.jpg', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.name, 'car.jpg');
    expect(result.wasCompressed, isTrue);
    expect(result.originalWidth, 3200);
    expect(result.originalHeight, 2400);
    expect(
      result.outputWidth,
      DriverApplicationUploadLimits.vehicleMaxLongEdge,
    );
    expect(result.outputHeight, lessThan(result.originalHeight!));
    expect(result.bytes.length, lessThan(source.length));
    expect(result.bytes.take(3), [0xff, 0xd8, 0xff]);
  });

  test('large vehicle PNG is converted to JPEG', () async {
    final source = _png(2600, 1800);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'car.png', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.name, 'car.jpg');
    expect(result.wasCompressed, isTrue);
    expect(
      result.outputWidth,
      DriverApplicationUploadLimits.vehicleMaxLongEdge,
    );
    expect(result.bytes.take(3), [0xff, 0xd8, 0xff]);
  });

  test('document images keep a higher long edge than vehicle photos', () async {
    final source = _jpeg(3200, 2400);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'insurance.jpg', bytes: source),
      category: DriverApplicationImageCategory.document,
    );

    expect(
      result.outputWidth,
      DriverApplicationUploadLimits.documentMaxLongEdge,
    );
    expect(
      result.outputWidth,
      greaterThan(DriverApplicationUploadLimits.vehicleMaxLongEdge),
    );
  });

  test('small JPEG is not recompressed', () async {
    final source = _jpeg(640, 480, quality: 82);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'small.jpg', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasCompressed, isFalse);
    expect(result.bytes, source);
    expect(result.outputWidth, 640);
    expect(result.outputHeight, 480);
  });

  test('small PNG is not recompressed', () async {
    final source = _png(640, 480);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'small.png', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasCompressed, isFalse);
    expect(result.name, 'small.png');
    expect(result.bytes, source);
    expect(result.outputWidth, 640);
    expect(result.outputHeight, 480);
  });

  test('line QR is not converted or recompressed', () async {
    final source = _png(600, 600);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'line.png', bytes: source),
      category: DriverApplicationImageCategory.lineQr,
    );

    expect(result.wasCompressed, isFalse);
    expect(result.name, 'line.png');
    expect(result.bytes, source);
  });

  test('unsupported HEIC-like bytes fail safely', () async {
    expect(
      () => service.prepare(
        const DriverApplicationUploadFile(
          name: 'photo.heic',
          bytes: [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70],
        ),
        category: DriverApplicationImageCategory.vehicle,
      ),
      throwsA(isA<DriverApplicationImageCompressionException>()),
    );
  });
}
