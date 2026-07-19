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

    final baked = img.bakeOrientation(decoded);
    baked.exif.clear();
    final policy = _policyFor(category);
    final originalLongEdge = math.max(baked.width, baked.height);
    final shouldKeepOriginal =
        bytes.length <= DriverApplicationUploadLimits.smallImageBytes &&
        originalLongEdge <= policy.maxLongEdge &&
        (_isJpeg(bytes) || _isPng(bytes));

    if (category == DriverApplicationImageCategory.lineQr ||
        shouldKeepOriginal) {
      return DriverApplicationUploadFile(
        name: file.name,
        bytes: file.bytes,
        originalByteLength: file.bytes.length,
        originalWidth: baked.width,
        originalHeight: baked.height,
        outputWidth: baked.width,
        outputHeight: baked.height,
        wasCompressed: false,
      );
    }

    final outputImage = _resizeWithin(baked, policy.maxLongEdge);
    outputImage.exif.clear();
    final outputBytes = img.encodeJpg(outputImage, quality: policy.quality);
    if (outputBytes.length >= bytes.length) {
      return DriverApplicationUploadFile(
        name: file.name,
        bytes: file.bytes,
        originalByteLength: file.bytes.length,
        originalWidth: baked.width,
        originalHeight: baked.height,
        outputWidth: baked.width,
        outputHeight: baked.height,
        wasCompressed: false,
      );
    }

    return DriverApplicationUploadFile(
      name: _jpgFilename(file.name),
      bytes: outputBytes,
      originalByteLength: file.bytes.length,
      originalWidth: baked.width,
      originalHeight: baked.height,
      outputWidth: outputImage.width,
      outputHeight: outputImage.height,
      wasCompressed: true,
    );
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
