import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../config/driver_application_upload_limits.dart';
import '../models/driver_application_models.dart';

enum DriverApplicationImageCategory { lineQr, vehicle, document }

class DriverApplicationImageCompressionException implements Exception {
  const DriverApplicationImageCompressionException();
}

class DriverApplicationImageCompressionService {
  const DriverApplicationImageCompressionService();

  Future<DriverApplicationUploadFile> prepare(
    DriverApplicationUploadFile file, {
    required DriverApplicationImageCategory category,
  }) async {
    final bytes = Uint8List.fromList(file.bytes);
    if (_isPdf(file.name, bytes)) {
      return file;
    }
    if (!_isSupportedImage(file.name, bytes)) {
      throw const DriverApplicationImageCompressionException();
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const DriverApplicationImageCompressionException();
    }

    final jpegOrientation = _isJpeg(bytes) ? _jpegExifOrientation(bytes) : null;
    final baked = img.Image.from(decoded);
    baked.exif.clear();
    final policy = _policyFor(category);
    final orientationApplied = jpegOrientation != null && jpegOrientation != 1;
    final originalLongEdge = math.max(baked.width, baked.height);
    final withinPolicy =
        originalLongEdge <= policy.maxLongEdge &&
        bytes.length <= DriverApplicationUploadLimits.smallImageBytes;

    if (_isJpeg(bytes)) {
      if (category == DriverApplicationImageCategory.lineQr &&
          !orientationApplied) {
        final strippedBytes = _stripJpegMetadata(bytes);
        return DriverApplicationUploadFile(
          name: file.name,
          bytes: strippedBytes,
          originalByteLength: file.bytes.length,
          originalWidth: baked.width,
          originalHeight: baked.height,
          outputWidth: baked.width,
          outputHeight: baked.height,
          wasCompressed: false,
          metadataStripped: strippedBytes.length != file.bytes.length,
        );
      }

      final outputImage = _resizeWithin(baked, policy.maxLongEdge);
      outputImage.exif.clear();
      final outputBytes = img.encodeJpg(outputImage, quality: policy.quality);
      return DriverApplicationUploadFile(
        name: _jpgFilename(file.name),
        bytes: outputBytes,
        originalByteLength: file.bytes.length,
        originalWidth: baked.width,
        originalHeight: baked.height,
        outputWidth: outputImage.width,
        outputHeight: outputImage.height,
        wasCompressed: outputBytes.length < file.bytes.length,
        wasReencoded: true,
        wasResized:
            outputImage.width != baked.width ||
            outputImage.height != baked.height,
        metadataStripped: true,
        orientationApplied: orientationApplied,
      );
    }

    if (_isPng(bytes)) {
      final strippedBytes = _stripPngMetadata(bytes);
      if (category == DriverApplicationImageCategory.lineQr || withinPolicy) {
        return DriverApplicationUploadFile(
          name: file.name,
          bytes: strippedBytes,
          originalByteLength: file.bytes.length,
          originalWidth: baked.width,
          originalHeight: baked.height,
          outputWidth: baked.width,
          outputHeight: baked.height,
          wasCompressed: false,
          metadataStripped: strippedBytes.length != file.bytes.length,
        );
      }

      final outputImage = _resizeWithin(baked, policy.maxLongEdge);
      outputImage.exif.clear();
      final outputBytes = img.encodeJpg(outputImage, quality: policy.quality);
      return DriverApplicationUploadFile(
        name: _jpgFilename(file.name),
        bytes: outputBytes,
        originalByteLength: file.bytes.length,
        originalWidth: baked.width,
        originalHeight: baked.height,
        outputWidth: outputImage.width,
        outputHeight: outputImage.height,
        wasCompressed: outputBytes.length < file.bytes.length,
        wasReencoded: true,
        wasResized:
            outputImage.width != baked.width ||
            outputImage.height != baked.height,
        metadataStripped: true,
      );
    }

    throw const DriverApplicationImageCompressionException();
  }

  bool _isPdf(String filename, Uint8List bytes) {
    return filename.toLowerCase().endsWith('.pdf') ||
        (bytes.length >= 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46);
  }

  bool _isSupportedImage(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    return _isJpeg(bytes) ||
        _isPng(bytes) ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  bool _isJpeg(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  bool _isPng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
  }

  Uint8List _stripJpegMetadata(Uint8List bytes) {
    if (!_isJpeg(bytes)) {
      throw const DriverApplicationImageCompressionException();
    }
    final output = BytesBuilder(copy: false)..add(bytes.sublist(0, 2));
    var offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xff) {
        throw const DriverApplicationImageCompressionException();
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset += 1;
      }
      if (offset >= bytes.length) {
        throw const DriverApplicationImageCompressionException();
      }
      final marker = bytes[offset];
      offset += 1;

      if (marker == 0xda) {
        output.add([0xff, marker]);
        output.add(bytes.sublist(offset));
        return output.takeBytes();
      }
      if (marker == 0xd9) {
        output.add([0xff, marker]);
        return output.takeBytes();
      }
      if (_isStandaloneJpegMarker(marker)) {
        output.add([0xff, marker]);
        continue;
      }
      if (offset + 2 > bytes.length) {
        throw const DriverApplicationImageCompressionException();
      }
      final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        throw const DriverApplicationImageCompressionException();
      }
      final segmentStart = offset - 2;
      final segmentEnd = offset + segmentLength;
      if (!_shouldRemoveJpegSegment(marker)) {
        output.add(bytes.sublist(segmentStart, segmentEnd));
      }
      offset = segmentEnd;
    }
    throw const DriverApplicationImageCompressionException();
  }

  bool _isStandaloneJpegMarker(int marker) {
    return marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7);
  }

  bool _shouldRemoveJpegSegment(int marker) {
    return marker == 0xe1 || marker == 0xed || marker == 0xfe;
  }

  int? _jpegExifOrientation(Uint8List bytes) {
    if (!_isJpeg(bytes)) return null;
    var offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xff) return null;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset += 1;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset];
      offset += 1;
      if (marker == 0xda || marker == 0xd9) return null;
      if (_isStandaloneJpegMarker(marker)) continue;
      if (offset + 2 > bytes.length) return null;
      final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return null;
      }
      final payloadStart = offset + 2;
      final payloadEnd = offset + segmentLength;
      if (marker == 0xe1 && payloadEnd - payloadStart > 14) {
        final orientation = _exifOrientationFromPayload(
          bytes,
          payloadStart,
          payloadEnd,
        );
        if (orientation != null) return orientation;
      }
      offset = payloadEnd;
    }
    return null;
  }

  int? _exifOrientationFromPayload(
    Uint8List bytes,
    int payloadStart,
    int payloadEnd,
  ) {
    const exifHeader = [0x45, 0x78, 0x69, 0x66, 0, 0];
    if (payloadEnd - payloadStart < exifHeader.length + 8) return null;
    for (var i = 0; i < exifHeader.length; i += 1) {
      if (bytes[payloadStart + i] != exifHeader[i]) return null;
    }
    final tiffStart = payloadStart + exifHeader.length;
    final littleEndian =
        bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final bigEndian = bytes[tiffStart] == 0x4d && bytes[tiffStart + 1] == 0x4d;
    if (!littleEndian && !bigEndian) return null;
    final magic = _readUint16(bytes, tiffStart + 2, littleEndian);
    if (magic != 0x2a) return null;
    final ifdOffset = _readUint32Endian(bytes, tiffStart + 4, littleEndian);
    final ifdStart = tiffStart + ifdOffset;
    if (ifdOffset < 8 || ifdStart + 2 > payloadEnd) return null;
    final entryCount = _readUint16(bytes, ifdStart, littleEndian);
    final entriesStart = ifdStart + 2;
    final entriesEnd = entriesStart + (entryCount * 12);
    if (entriesEnd > payloadEnd) return null;
    for (var entry = entriesStart; entry < entriesEnd; entry += 12) {
      final tag = _readUint16(bytes, entry, littleEndian);
      if (tag != 0x0112) continue;
      final type = _readUint16(bytes, entry + 2, littleEndian);
      final count = _readUint32Endian(bytes, entry + 4, littleEndian);
      if (type != 3 || count != 1) return null;
      final value = _readUint16(bytes, entry + 8, littleEndian);
      return value >= 1 && value <= 8 ? value : null;
    }
    return null;
  }

  int _readUint16(Uint8List bytes, int offset, bool littleEndian) {
    if (littleEndian) {
      return bytes[offset] | (bytes[offset + 1] << 8);
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  int _readUint32Endian(Uint8List bytes, int offset, bool littleEndian) {
    if (littleEndian) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
    }
    return _readUint32(bytes, offset);
  }

  Uint8List _stripPngMetadata(Uint8List bytes) {
    if (!_isPng(bytes)) {
      throw const DriverApplicationImageCompressionException();
    }
    final output = BytesBuilder(copy: false)..add(bytes.sublist(0, 8));
    var offset = 8;
    while (offset < bytes.length) {
      if (offset + 12 > bytes.length) {
        throw const DriverApplicationImageCompressionException();
      }
      final length = _readUint32(bytes, offset);
      final typeStart = offset + 4;
      final dataStart = offset + 8;
      final crcStart = dataStart + length;
      final chunkEnd = crcStart + 4;
      if (length < 0 || chunkEnd > bytes.length) {
        throw const DriverApplicationImageCompressionException();
      }
      final type = String.fromCharCodes(bytes.sublist(typeStart, dataStart));
      if (!_shouldRemovePngChunk(type)) {
        output.add(bytes.sublist(offset, chunkEnd));
      }
      offset = chunkEnd;
      if (type == 'IEND') {
        if (offset != bytes.length) {
          throw const DriverApplicationImageCompressionException();
        }
        return output.takeBytes();
      }
    }
    throw const DriverApplicationImageCompressionException();
  }

  int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  bool _shouldRemovePngChunk(String type) {
    return type == 'eXIf' ||
        type == 'tEXt' ||
        type == 'zTXt' ||
        type == 'iTXt' ||
        type == 'tIME';
  }

  _CompressionPolicy _policyFor(DriverApplicationImageCategory category) {
    return switch (category) {
      DriverApplicationImageCategory.vehicle => const _CompressionPolicy(
        maxLongEdge: DriverApplicationUploadLimits.vehicleMaxLongEdge,
        quality: DriverApplicationUploadLimits.vehicleJpegQuality,
      ),
      DriverApplicationImageCategory.document => const _CompressionPolicy(
        maxLongEdge: DriverApplicationUploadLimits.documentMaxLongEdge,
        quality: DriverApplicationUploadLimits.documentJpegQuality,
      ),
      DriverApplicationImageCategory.lineQr => const _CompressionPolicy(
        maxLongEdge: DriverApplicationUploadLimits.documentMaxLongEdge,
        quality: DriverApplicationUploadLimits.documentJpegQuality,
      ),
    };
  }

  img.Image _resizeWithin(img.Image source, int maxLongEdge) {
    final longEdge = math.max(source.width, source.height);
    if (longEdge <= maxLongEdge) return source;
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxLongEdge);
    }
    return img.copyResize(source, height: maxLongEdge);
  }

  String _jpgFilename(String filename) {
    final safeName = filename
        .split(RegExp(r'[?#]'))
        .first
        .split(RegExp(r'[\\/]'))
        .last;
    final dot = safeName.lastIndexOf('.');
    final base = dot <= 0 ? safeName : safeName.substring(0, dot);
    return '${base.isEmpty ? 'upload' : base}.jpg';
  }
}

class _CompressionPolicy {
  const _CompressionPolicy({required this.maxLongEdge, required this.quality});

  final int maxLongEdge;
  final int quality;
}
