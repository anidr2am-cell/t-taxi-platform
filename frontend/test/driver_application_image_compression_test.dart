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

Uint8List _withJpegSegments(
  Uint8List source, {
  int orientation = 1,
  bool includePrivacyPayload = true,
}) {
  final segments = <int>[
    ..._jpegSegment(0xe1, _exifPayload(orientation)),
    ..._jpegSegment(
      0xe1,
      Uint8List.fromList(
        'http://ns.adobe.com/xap/1.0/\x00GPSLatitude Make Model DateTimeOriginal'
            .codeUnits,
      ),
    ),
    ..._jpegSegment(0xed, Uint8List.fromList('IPTC UserComment'.codeUnits)),
    ..._jpegSegment(0xfe, Uint8List.fromList('Camera comment'.codeUnits)),
    if (includePrivacyPayload)
      ..._jpegSegment(
        0xe1,
        Uint8List.fromList(
          'GPSLongitude DateTimeDigitized LensModel SerialNumber'.codeUnits,
        ),
      ),
  ];
  return Uint8List.fromList([
    ...source.take(2),
    ...segments,
    ...source.skip(2),
  ]);
}

Uint8List _jpegSegment(int marker, Uint8List payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xff,
    marker,
    (length >> 8) & 0xff,
    length & 0xff,
    ...payload,
  ]);
}

Uint8List _exifPayload(int orientation) {
  final payload = <int>[
    ...'Exif'.codeUnits,
    0,
    0,
    ...'II'.codeUnits,
    0x2a,
    0,
    8,
    0,
    0,
    0,
    1,
    0,
    0x12,
    0x01,
    3,
    0,
    1,
    0,
    0,
    0,
    orientation,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  return Uint8List.fromList(payload);
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

Uint8List _pngWithTextMetadata(Uint8List source) {
  final insertAt = source.length - 12;
  final textChunk = _pngChunk(
    'tEXt',
    Uint8List.fromList('Make\x00Synthetic Camera GPSLatitude'.codeUnits),
  );
  final timeChunk = _pngChunk(
    'tIME',
    Uint8List.fromList([7, 0xe8, 1, 2, 3, 4, 5]),
  );
  return Uint8List.fromList([
    ...source.take(insertAt),
    ...textChunk,
    ...timeChunk,
    ...source.skip(insertAt),
  ]);
}

Uint8List _pngChunk(String type, Uint8List data) {
  final bytes = <int>[
    (data.length >> 24) & 0xff,
    (data.length >> 16) & 0xff,
    (data.length >> 8) & 0xff,
    data.length & 0xff,
    ...type.codeUnits,
    ...data,
    0,
    0,
    0,
    0,
  ];
  return Uint8List.fromList(bytes);
}

String _latin1(Uint8List bytes) => String.fromCharCodes(bytes);

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

  test('small JPEG is privacy processed instead of passed through', () async {
    final source = _withJpegSegments(_jpeg(640, 480, quality: 82));
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'small.jpg', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasReencoded, isTrue);
    expect(result.metadataStripped, isTrue);
    expect(result.bytes, isNot(source));
    expect(result.outputWidth, 640);
    expect(result.outputHeight, 480);
    final outputText = _latin1(Uint8List.fromList(result.bytes));
    expect(outputText, isNot(contains('GPSLatitude')));
    expect(outputText, isNot(contains('Make')));
    expect(outputText, isNot(contains('DateTimeOriginal')));
    expect(outputText, isNot(contains('IPTC')));
    expect(outputText, isNot(contains('Camera comment')));
  });

  test('small JPEG orientation 6 is baked into output pixels', () async {
    final source = _withJpegSegments(
      _jpeg(120, 80, quality: 90),
      orientation: 6,
    );
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'rotated.jpg', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasReencoded, isTrue);
    expect(result.orientationApplied, isTrue);
    expect(result.outputWidth, 80);
    expect(result.outputHeight, 120);
    final decoded = img.decodeImage(Uint8List.fromList(result.bytes));
    expect(decoded?.width, 80);
    expect(decoded?.height, 120);
    expect(decoded?.exif.imageIfd['Orientation'], isNull);
  });

  test('small JPEG orientation 3 and 8 are handled safely', () async {
    final upsideDown = await service.prepare(
      DriverApplicationUploadFile(
        name: 'orientation-3.jpg',
        bytes: _withJpegSegments(_jpeg(120, 80, quality: 90), orientation: 3),
      ),
      category: DriverApplicationImageCategory.vehicle,
    );
    final rotated = await service.prepare(
      DriverApplicationUploadFile(
        name: 'orientation-8.jpg',
        bytes: _withJpegSegments(_jpeg(120, 80, quality: 90), orientation: 8),
      ),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(upsideDown.orientationApplied, isTrue);
    expect(upsideDown.outputWidth, 120);
    expect(upsideDown.outputHeight, 80);
    expect(rotated.orientationApplied, isTrue);
    expect(rotated.outputWidth, 80);
    expect(rotated.outputHeight, 120);
  });

  test('small PNG is not recompressed', () async {
    final source = _pngWithTextMetadata(_png(640, 480));
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'small.png', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasCompressed, isFalse);
    expect(result.metadataStripped, isTrue);
    expect(result.name, 'small.png');
    expect(result.bytes, isNot(source));
    expect(
      _latin1(Uint8List.fromList(result.bytes)),
      isNot(contains('GPSLatitude')),
    );
    expect(result.outputWidth, 640);
    expect(result.outputHeight, 480);
  });

  test('line QR is not converted or recompressed', () async {
    final source = _pngWithTextMetadata(_png(600, 600));
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'line.png', bytes: source),
      category: DriverApplicationImageCategory.lineQr,
    );

    expect(result.wasCompressed, isFalse);
    expect(result.wasReencoded, isFalse);
    expect(result.metadataStripped, isTrue);
    expect(result.name, 'line.png');
    expect(result.bytes.take(8), source.take(8));
    expect(
      _latin1(Uint8List.fromList(result.bytes)),
      isNot(contains('GPSLatitude')),
    );
  });

  test('PDF behavior is unchanged', () async {
    final source = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2, 3]);
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'document.pdf', bytes: source),
      category: DriverApplicationImageCategory.document,
    );

    expect(result.bytes, source);
    expect(result.metadataStripped, isFalse);
    expect(result.wasReencoded, isFalse);
  });

  test('large JPEG resize still strips metadata', () async {
    final source = _withJpegSegments(_jpeg(3200, 2400));
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'large.jpg', bytes: source),
      category: DriverApplicationImageCategory.vehicle,
    );

    expect(result.wasReencoded, isTrue);
    expect(result.wasResized, isTrue);
    expect(result.metadataStripped, isTrue);
    expect(
      _latin1(Uint8List.fromList(result.bytes)),
      isNot(contains('GPSLatitude')),
    );
  });

  test('document JPEG is reencoded with metadata removed', () async {
    final source = _withJpegSegments(_jpeg(900, 600, quality: 90));
    final result = await service.prepare(
      DriverApplicationUploadFile(name: 'document.jpg', bytes: source),
      category: DriverApplicationImageCategory.document,
    );

    expect(result.name, 'document.jpg');
    expect(result.wasReencoded, isTrue);
    expect(result.metadataStripped, isTrue);
    expect(result.outputWidth, 900);
    expect(result.outputHeight, 600);
    expect(_latin1(Uint8List.fromList(result.bytes)), isNot(contains('Model')));
  });

  test('malformed JPEG fails safely without original passthrough', () async {
    expect(
      () => service.prepare(
        const DriverApplicationUploadFile(
          name: 'broken.jpg',
          bytes: [0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff, 1, 2, 3],
        ),
        category: DriverApplicationImageCategory.vehicle,
      ),
      throwsA(isA<DriverApplicationImageCompressionException>()),
    );
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
