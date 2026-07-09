import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

class GuestDriverVehiclePhoto extends StatefulWidget {
  const GuestDriverVehiclePhoto({
    super.key,
    required this.photoPath,
    required this.guestAccessToken,
    this.apiBaseUrl,
    this.height = 190,
    this.client,
  });

  final String photoPath;
  final String guestAccessToken;
  final String? apiBaseUrl;
  final double height;
  final http.Client? client;

  @override
  State<GuestDriverVehiclePhoto> createState() => _GuestDriverVehiclePhotoState();
}

class _GuestDriverVehiclePhotoState extends State<GuestDriverVehiclePhoto> {
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
  void didUpdateWidget(covariant GuestDriverVehiclePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath ||
        oldWidget.guestAccessToken != widget.guestAccessToken) {
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
    final path = widget.photoPath.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = (widget.apiBaseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/$'), '');
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
          'X-Guest-Access-Token': widget.guestAccessToken,
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
    final l10n = context.l10n;

    if (_loading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_failed || _bytes == null) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Text(
          l10n.t('guest_lookup_vehicle_photo_load_failed'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTokens.textSecondary,
            height: 1.4,
          ),
        ),
      );
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
