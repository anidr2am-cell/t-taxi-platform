import 'dart:convert';

/// Storage schema version for attribution records in localStorage.
const marketingAttributionSchemaVersion = 2;

/// First / last touch attribution TTL (Thailand travel search-to-book window).
const marketingAttributionTtlDays = 90;

/// Sanitizes UTM values, paths, and referrers before GA4 or DB use.
abstract final class MarketingAttributionSanitizer {
  static final RegExp _utmPattern = RegExp(r'^[a-zA-Z0-9._-]{1,150}$');
  static final RegExp _emailPattern = RegExp(r'[^@]+@[^@]+\.[^@]+');
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9\s()-]{7,20}$');

  static String? utmValue(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 150) return null;
    if (_looksLikePii(trimmed)) return null;
    if (!_utmPattern.hasMatch(trimmed)) return null;
    return trimmed;
  }

  static String? landingPath(Uri uri) {
    var path = uri.path;
    if (path.isEmpty) path = '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 500) return null;
    if (path.contains('?') || path.contains('#')) return null;
    return path;
  }

  static String? referrerHost(String? referrer) {
    if (referrer == null || referrer.trim().isEmpty) return null;
    try {
      final host = Uri.parse(referrer.trim()).host.trim().toLowerCase();
      if (host.isEmpty || host.length > 255) return null;
      if (_looksLikePii(host)) return null;
      if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) return null;
      return host;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikePii(String value) {
    final lower = value.toLowerCase();
    if (_emailPattern.hasMatch(lower)) return true;
    if (_phonePattern.hasMatch(value.replaceAll(' ', ''))) return true;
    if (lower.contains('@')) return true;
    return false;
  }
}

/// One marketing touch point (UTM + landing context).
class MarketingTouch {
  const MarketingTouch({
    this.source,
    this.medium,
    this.campaign,
    this.content,
    this.term,
    this.landingPage,
    this.referrerHost,
    required this.capturedAt,
    this.expiresAt,
    this.schemaVersion = marketingAttributionSchemaVersion,
  });

  factory MarketingTouch.fromJson(Map<String, dynamic> json) {
    return MarketingTouch(
      source: MarketingAttributionSanitizer.utmValue(
        json['source']?.toString(),
      ),
      medium: MarketingAttributionSanitizer.utmValue(
        json['medium']?.toString(),
      ),
      campaign: MarketingAttributionSanitizer.utmValue(
        json['campaign']?.toString(),
      ),
      content: MarketingAttributionSanitizer.utmValue(
        json['content']?.toString(),
      ),
      term: MarketingAttributionSanitizer.utmValue(json['term']?.toString()),
      landingPage: _optionalPath(json['landing_page'] ?? json['landingPage']),
      referrerHost: MarketingAttributionSanitizer.referrerHost(
        json['referrer_host']?.toString() ?? json['referrerHost']?.toString(),
      ),
      capturedAt: json['captured_at'] as String? ??
          json['capturedAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      expiresAt: json['expires_at'] as String? ?? json['expiresAt'] as String?,
      schemaVersion: json['schema_version'] as int? ??
          json['schemaVersion'] as int? ??
          marketingAttributionSchemaVersion,
    );
  }

  final String? source;
  final String? medium;
  final String? campaign;
  final String? content;
  final String? term;
  final String? landingPage;
  final String? referrerHost;
  final String capturedAt;
  final String? expiresAt;
  final int schemaVersion;

  bool get hasCampaignSignal =>
      [source, medium, campaign, content, term].any(
        (value) => value != null && value.isNotEmpty,
      );

  bool get hasAnySignal =>
      hasCampaignSignal ||
      (landingPage != null && landingPage!.isNotEmpty) ||
      (referrerHost != null && referrerHost!.isNotEmpty);

  bool isExpiredAt(DateTime now) {
    final raw = expiresAt;
    if (raw == null || raw.isEmpty) return false;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;
    return !parsed.isAfter(now);
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (source != null) 'source': source,
        if (medium != null) 'medium': medium,
        if (campaign != null) 'campaign': campaign,
        if (content != null) 'content': content,
        if (term != null) 'term': term,
        if (landingPage != null) 'landing_page': landingPage,
        if (referrerHost != null) 'referrer_host': referrerHost,
        'captured_at': capturedAt,
        'expires_at': expiresAt,
      };

  Map<String, dynamic> toApiJson() => {
        if (source != null) 'source': source,
        if (medium != null) 'medium': medium,
        if (campaign != null) 'campaign': campaign,
        if (content != null) 'content': content,
        if (term != null) 'term': term,
        if (landingPage != null) 'landingPage': landingPage,
        if (referrerHost != null) 'referrerHost': referrerHost,
        'capturedAt': capturedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
      };

  static String? _optionalPath(Object? value) {
    if (value == null) return null;
    final normalized = value.toString().trim();
    if (normalized.isEmpty || !normalized.startsWith('/')) return null;
    if (normalized.contains('?') || normalized.contains('#')) return null;
    return normalized.length <= 500 ? normalized : null;
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class MarketingAttributionSnapshot {
  const MarketingAttributionSnapshot({
    this.firstTouch,
    this.lastTouch,
  });

  final MarketingTouch? firstTouch;
  final MarketingTouch? lastTouch;

  bool get isEmpty => firstTouch == null && lastTouch == null;

  Map<String, dynamic> toApiJson() => {
        if (firstTouch != null) 'firstTouch': firstTouch!.toApiJson(),
        if (lastTouch != null) 'lastTouch': lastTouch!.toApiJson(),
      };

  Map<String, Object?> analyticsParams() {
    final touch = lastTouch ?? firstTouch;
    if (touch == null) return const {};
    return {
      if (touch.source != null) 'traffic_source': touch.source,
      if (touch.medium != null) 'traffic_medium': touch.medium,
      if (touch.campaign != null) 'traffic_campaign': touch.campaign,
      if (touch.content != null) 'traffic_content': touch.content,
    };
  }
}

abstract class MarketingAttributionStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class InMemoryMarketingAttributionStorage implements MarketingAttributionStorage {
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);

  void clear() => _values.clear();
}

class MarketingAttributionService {
  MarketingAttributionService(this._storage);

  static const firstTouchKey = 'tride_marketing_first_touch';
  static const lastTouchKey = 'tride_marketing_last_touch';

  final MarketingAttributionStorage _storage;

  MarketingAttributionSnapshot readSnapshot({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    return MarketingAttributionSnapshot(
      firstTouch: _readTouch(firstTouchKey, effectiveNow),
      lastTouch: _readTouch(lastTouchKey, effectiveNow),
    );
  }

  void clearAll() {
    _storage.remove(firstTouchKey);
    _storage.remove(lastTouchKey);
  }

  MarketingAttributionSnapshot applySnapshot(
    MarketingAttributionSnapshot snapshot, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    if (snapshot.firstTouch != null) {
      _writeTouch(firstTouchKey, snapshot.firstTouch!, effectiveNow);
    }
    if (snapshot.lastTouch != null) {
      _writeTouch(lastTouchKey, snapshot.lastTouch!, effectiveNow);
    }
    return readSnapshot(now: effectiveNow);
  }

  MarketingAttributionSnapshot mergeIncoming({
    required MarketingAttributionSnapshot? existing,
    required MarketingTouch? incomingTouch,
    required String? landingPage,
    required String? referrerHost,
    required DateTime now,
  }) {
    final capturedAt = now.toUtc().toIso8601String();
    final expiresAt = _expiresAt(now);

    MarketingTouch? firstTouch = existing?.firstTouch;
    MarketingTouch? lastTouch = existing?.lastTouch;

    if (incomingTouch != null && incomingTouch.hasAnySignal) {
      final touch = MarketingTouch(
        source: incomingTouch.source,
        medium: incomingTouch.medium,
        campaign: incomingTouch.campaign,
        content: incomingTouch.content,
        term: incomingTouch.term,
        landingPage: incomingTouch.landingPage ?? landingPage,
        referrerHost: incomingTouch.referrerHost ?? referrerHost,
        capturedAt: capturedAt,
        expiresAt: expiresAt,
      );

      if (firstTouch == null) {
        firstTouch = touch;
      }
      if (touch.hasCampaignSignal) {
        lastTouch = touch;
      }
    } else if (firstTouch == null && landingPage != null) {
      firstTouch = MarketingTouch(
        landingPage: landingPage,
        referrerHost: referrerHost,
        capturedAt: capturedAt,
        expiresAt: expiresAt,
      );
    }

    return MarketingAttributionSnapshot(
      firstTouch: firstTouch,
      lastTouch: lastTouch,
    );
  }

  static MarketingTouch? touchFromUri({
    required Uri uri,
    String? documentReferrer,
    DateTime? now,
  }) {
    final utmParams = _readUtm(uri);
    final landingPage = MarketingAttributionSanitizer.landingPath(uri);
    final referrerHost = MarketingAttributionSanitizer.referrerHost(
      documentReferrer,
    );
    final hasUtm = utmParams.values.any((value) => value != null);

    if (!hasUtm && referrerHost == null && landingPage == null) {
      return null;
    }

    final capturedAt = (now ?? DateTime.now()).toUtc().toIso8601String();
    return MarketingTouch(
      source: utmParams['utm_source'],
      medium: utmParams['utm_medium'],
      campaign: utmParams['utm_campaign'],
      content: utmParams['utm_content'],
      term: utmParams['utm_term'],
      landingPage: landingPage,
      referrerHost: referrerHost,
      capturedAt: capturedAt,
      expiresAt: _expiresAt(now ?? DateTime.now()),
    );
  }

  MarketingTouch? _readTouch(String key, DateTime now) {
    final raw = _storage.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _storage.remove(key);
        return null;
      }
      final touch = MarketingTouch.fromJson(decoded);
      if (!touch.hasAnySignal || touch.isExpiredAt(now)) {
        _storage.remove(key);
        return null;
      }
      return touch;
    } catch (_) {
      _storage.remove(key);
      return null;
    }
  }

  void _writeTouch(String key, MarketingTouch touch, DateTime now) {
    if (!touch.hasAnySignal) return;
    final payload = MarketingTouch(
      source: touch.source,
      medium: touch.medium,
      campaign: touch.campaign,
      content: touch.content,
      term: touch.term,
      landingPage: touch.landingPage,
      referrerHost: touch.referrerHost,
      capturedAt: touch.capturedAt,
      expiresAt: touch.expiresAt ?? _expiresAt(now),
    );
    _storage.write(key, jsonEncode(payload.toJson()));
  }

  static String _expiresAt(DateTime from) {
    return from
        .toUtc()
        .add(const Duration(days: marketingAttributionTtlDays))
        .toIso8601String();
  }

  static Map<String, String?> _readUtm(Uri uri) {
    String? pick(String name) =>
        MarketingAttributionSanitizer.utmValue(uri.queryParameters[name]);

    return {
      'utm_source': pick('utm_source'),
      'utm_medium': pick('utm_medium'),
      'utm_campaign': pick('utm_campaign'),
      'utm_content': pick('utm_content'),
      'utm_term': pick('utm_term'),
    };
  }
}

/// Consent-gated attribution coordinator (memory until analytics is granted).
class MarketingAttributionCoordinator {
  MarketingAttributionCoordinator({
    required MarketingAttributionService service,
  }) : _service = service;

  final MarketingAttributionService _service;
  MarketingAttributionSnapshot? _pendingSnapshot;
  Uri? _lastLandingUri;
  String? _lastReferrer;

  void captureLanding({
    required Uri uri,
    String? documentReferrer,
    required bool analyticsGranted,
    required bool analyticsDenied,
    DateTime? now,
  }) {
    _lastLandingUri = uri;
    _lastReferrer = documentReferrer;
    final effectiveNow = now ?? DateTime.now().toUtc();
    final incoming = MarketingAttributionService.touchFromUri(
      uri: uri,
      documentReferrer: documentReferrer,
      now: effectiveNow,
    );
    final landingPage = MarketingAttributionSanitizer.landingPath(uri);
    final referrerHost = MarketingAttributionSanitizer.referrerHost(
      documentReferrer,
    );

    if (analyticsDenied) {
      _pendingSnapshot = null;
      return;
    }

    if (analyticsGranted) {
      final merged = _service.mergeIncoming(
        existing: _service.readSnapshot(now: effectiveNow),
        incomingTouch: incoming,
        landingPage: landingPage,
        referrerHost: referrerHost,
        now: effectiveNow,
      );
      _service.applySnapshot(merged, now: effectiveNow);
      _pendingSnapshot = null;
      return;
    }

    _pendingSnapshot = _service.mergeIncoming(
      existing: _pendingSnapshot,
      incomingTouch: incoming,
      landingPage: landingPage,
      referrerHost: referrerHost,
      now: effectiveNow,
    );
  }

  void onAnalyticsGranted({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    if (_pendingSnapshot != null && !_pendingSnapshot!.isEmpty) {
      _service.applySnapshot(_pendingSnapshot!, now: effectiveNow);
      _pendingSnapshot = null;
    } else if (_lastLandingUri != null) {
      captureLanding(
        uri: _lastLandingUri!,
        documentReferrer: _lastReferrer,
        analyticsGranted: true,
        analyticsDenied: false,
        now: effectiveNow,
      );
    }
  }

  void onAnalyticsDenied() {
    _pendingSnapshot = null;
    _service.clearAll();
  }

  MarketingAttributionSnapshot? snapshotForBooking({DateTime? now}) {
    final snapshot = _service.readSnapshot(now: now);
    return snapshot.isEmpty ? null : snapshot;
  }

  MarketingAttributionSnapshot? snapshotForAnalytics({DateTime? now}) {
    return snapshotForBooking(now: now);
  }
}
