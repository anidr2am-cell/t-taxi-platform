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
    this.guestAccessToken = '',
    this.customerAccessToken,
    this.useCustomerAuth = false,
    this.apiBaseUrl,
    this.height = 190,
    this.client,
  });

  final String photoPath;
  final String guestAccessToken;
  final String? customerAccessToken;
  final bool useCustomerAuth;
  final String? apiBaseUrl;
  final double height;
  final http.Client? client;

  @override
  State<GuestDriverVehiclePhoto> createState() =>
      _GuestDriverVehiclePhotoState();
}

class _GuestDriverVehiclePhotoState extends State<GuestDriverVehiclePhoto> {
  late final http.Client _client = widget.client ?? http.Client();
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;
  bool _needsAuth = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GuestDriverVehiclePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath ||
        oldWidget.guestAccessToken != widget.guestAccessToken ||
        oldWidget.customerAccessToken != widget.customerAccessToken ||
        oldWidget.useCustomerAuth != widget.useCustomerAuth) {
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
      final target = Uri.parse(path);
      final origin = Uri.parse(widget.apiBaseUrl ?? AppConfig.apiBaseUrl);
      if (target.origin != origin.origin)
        throw const FormatException('Foreign photo origin');
      return path;
    }
    final base = (widget.apiBaseUrl ?? AppConfig.apiBaseUrl).replaceAll(
      RegExp(r'/$'),
      '',
    );
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  Map<String, String>? _authHeaders() {
    final guestToken = widget.guestAccessToken.trim();
    final customerToken = widget.customerAccessToken?.trim() ?? '';

    if (widget.useCustomerAuth && customerToken.isNotEmpty) {
      return {'Accept': 'image/*', 'Authorization': 'Bearer $customerToken'};
    }

    if (guestToken.isNotEmpty) {
      return {'Accept': 'image/*', 'X-Guest-Access-Token': guestToken};
    }

    if (customerToken.isNotEmpty) {
      return {'Accept': 'image/*', 'Authorization': 'Bearer $customerToken'};
    }

    return null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _needsAuth = false;
      _bytes = null;
    });

    final headers = _authHeaders();
    if (headers == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _needsAuth = true;
      });
      return;
    }

    try {
      final response = await _client
          .get(Uri.parse(_resolveUrl()), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        setState(() {
          _loading = false;
          _failed = true;
          _needsAuth = response.statusCode == 401 || response.statusCode == 403;
        });
        return;
      }
      setState(() {
        _bytes = response.bodyBytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Widget _unavailable(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: widget.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.t(
              _needsAuth
                  ? 'voucher_edit_auth_error'
                  : 'voucher_edit_photo_pending',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
          TextButton(
            onPressed: _load,
            child: Text(l10n.t('voucher_edit_retry')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    if (_failed || _bytes == null) return _unavailable(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Image.memory(
          _bytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _unavailable(context),
        ),
      ),
    );
  }
}
