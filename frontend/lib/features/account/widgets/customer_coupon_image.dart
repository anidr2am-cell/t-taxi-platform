import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../theme/app_tokens.dart';

class CustomerCouponImage extends StatefulWidget {
  const CustomerCouponImage({
    super.key,
    required this.imageUrl,
    required this.accessToken,
    this.height = 120,
    this.client,
  });

  final String imageUrl;
  final String accessToken;
  final double height;
  final http.Client? client;

  @override
  State<CustomerCouponImage> createState() => _CustomerCouponImageState();
}

class _CustomerCouponImageState extends State<CustomerCouponImage> {
  late final http.Client _client = widget.client ?? http.Client();
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomerCouponImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.accessToken != widget.accessToken) {
      _load();
    }
  }

  @override
  void dispose() {
    if (widget.client == null) {
      _client.close();
    }
    super.dispose();
  }

  String _resolveUrl() {
    final path = widget.imageUrl.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _bytes = null;
    });

    try {
      final response = await _client.get(
        Uri.parse(_resolveUrl()),
        headers: {
          'Accept': 'image/*',
          'Authorization': 'Bearer ${widget.accessToken}',
        },
      );
      if (!mounted) return;
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      setState(() {
        _bytes = response.bodyBytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_failed || _bytes == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Image.memory(
          _bytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
