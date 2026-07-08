import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class SupportInquiryApiException implements Exception {
  const SupportInquiryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupportInquiryAttachmentDraft {
  const SupportInquiryAttachmentDraft({required this.name, this.bytes});

  final String name;
  final Uint8List? bytes;
}

class SupportInquiryReceipt {
  const SupportInquiryReceipt({
    required this.publicId,
    this.lookupToken,
    required this.status,
    this.createdAt,
  });

  final String publicId;
  final String? lookupToken;
  final String status;
  final String? createdAt;

  factory SupportInquiryReceipt.fromJson(Map<String, dynamic> json) {
    return SupportInquiryReceipt(
      publicId: json['publicId'] as String? ?? '',
      lookupToken: json['lookupToken'] as String?,
      status: json['status'] as String? ?? 'NEW',
      createdAt: json['createdAt'] as String?,
    );
  }
}

class SupportInquiryMessage {
  const SupportInquiryMessage({
    required this.senderType,
    required this.message,
    this.createdAt,
  });

  final String senderType;
  final String message;
  final String? createdAt;

  factory SupportInquiryMessage.fromJson(Map<String, dynamic> json) {
    return SupportInquiryMessage(
      senderType: json['senderType'] as String? ?? 'SYSTEM',
      message: json['message'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
    );
  }
}

class SupportInquiryThread {
  const SupportInquiryThread({
    required this.publicId,
    required this.status,
    required this.messages,
  });

  final String publicId;
  final String status;
  final List<SupportInquiryMessage> messages;

  factory SupportInquiryThread.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'] as List<dynamic>? ?? const [];
    return SupportInquiryThread(
      publicId: json['publicId'] as String? ?? '',
      status: json['status'] as String? ?? 'NEW',
      messages: messages
          .whereType<Map>()
          .map(
            (item) =>
                SupportInquiryMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }
}

class SupportInquiryLookup {
  const SupportInquiryLookup({required this.publicId, required this.token});

  final String publicId;
  final String token;
}

class SupportInquiryApiService {
  SupportInquiryApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  String get _base => '$_baseUrl/api/v1';

  static const _lookupPublicIdKey = 'support_inquiry_public_id';
  static const _lookupTokenKey = 'support_inquiry_lookup_token';

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  String _extension(String filename) {
    final safeName = filename
        .split(RegExp(r'[?#]'))
        .first
        .split(RegExp(r'[\\/]'))
        .last;
    final dot = safeName.lastIndexOf('.');
    if (dot < 0 || dot == safeName.length - 1) return '';
    return safeName.substring(dot + 1).toLowerCase();
  }

  MediaType? _contentTypeFor(String filename) {
    final ext = _extension(filename);
    if (!_imageExtensions.contains(ext)) return null;
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
    return MediaType.parse(mimeType);
  }

  Future<SupportInquiryReceipt> submit({
    required String message,
    String? customerName,
    String? customerPhone,
    String? kakaoId,
    String? lineId,
    String? locale,
    List<SupportInquiryAttachmentDraft> attachments = const [],
  }) async {
    if (attachments.isEmpty) {
      final response = await _client.post(
        Uri.parse('$_base/support/inquiries'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': message,
          if (customerName != null && customerName.trim().isNotEmpty)
            'customerName': customerName.trim(),
          if (customerPhone != null && customerPhone.trim().isNotEmpty)
            'customerPhone': customerPhone.trim(),
          if (kakaoId != null && kakaoId.trim().isNotEmpty)
            'kakaoId': kakaoId.trim(),
          if (lineId != null && lineId.trim().isNotEmpty)
            'lineId': lineId.trim(),
          if (locale != null && locale.isNotEmpty) 'locale': locale,
        }),
      );
      return _decodeReceipt(response);
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/support/inquiries'),
    );
    request.headers['Accept'] = 'application/json';
    request.fields['message'] = message;
    if (customerName != null && customerName.trim().isNotEmpty) {
      request.fields['customerName'] = customerName.trim();
    }
    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      request.fields['customerPhone'] = customerPhone.trim();
    }
    if (kakaoId != null && kakaoId.trim().isNotEmpty) {
      request.fields['kakaoId'] = kakaoId.trim();
    }
    if (lineId != null && lineId.trim().isNotEmpty) {
      request.fields['lineId'] = lineId.trim();
    }
    if (locale != null && locale.isNotEmpty) request.fields['locale'] = locale;
    for (final file in attachments) {
      final bytes = file.bytes;
      final contentType = _contentTypeFor(file.name);
      if (bytes == null || contentType == null) {
        throw const SupportInquiryApiException('Invalid file type');
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'attachments',
          bytes,
          filename: file.name,
          contentType: contentType,
        ),
      );
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decodeReceipt(response);
  }

  Future<SupportInquiryThread> getThread({
    required String publicId,
    required String lookupToken,
  }) async {
    final response = await _client.get(
      Uri.parse('$_base/support/inquiries/$publicId'),
      headers: {
        'Accept': 'application/json',
        'X-Support-Lookup-Token': lookupToken,
      },
    );
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw SupportInquiryApiException(message);
    }
    if (decoded is Map && decoded['data'] is Map) {
      return SupportInquiryThread.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
    }
    throw const SupportInquiryApiException('Invalid support inquiry response');
  }

  Future<void> saveLatestLookup(SupportInquiryReceipt receipt) async {
    final token = receipt.lookupToken;
    if (receipt.publicId.isEmpty || token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lookupPublicIdKey, receipt.publicId);
    await prefs.setString(_lookupTokenKey, token);
  }

  Future<SupportInquiryLookup?> loadLatestLookup() async {
    final prefs = await SharedPreferences.getInstance();
    final publicId = prefs.getString(_lookupPublicIdKey);
    final token = prefs.getString(_lookupTokenKey);
    if (publicId == null ||
        publicId.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return SupportInquiryLookup(publicId: publicId, token: token);
  }

  SupportInquiryReceipt _decodeReceipt(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      throw SupportInquiryApiException(message);
    }
    if (decoded is Map && decoded['data'] is Map) {
      return SupportInquiryReceipt.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
    }
    throw const SupportInquiryApiException('Invalid support inquiry response');
  }
}
