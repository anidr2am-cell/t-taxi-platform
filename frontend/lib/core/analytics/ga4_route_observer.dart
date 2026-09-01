import 'package:flutter/material.dart';

import 'ga4_booking_analytics_sink.dart';

/// Sends manual SPA page_view events to GA4 (send_page_view disabled in config).
class Ga4RouteObserver extends RouteObserver<PageRoute<dynamic>> {
  Ga4RouteObserver();

  String? _lastPath;

  void trackInitialRoute(String? routeName) {
    final path = _normalizePath(routeName);
    if (path == null) return;
    _lastPath = path;
    Ga4AnalyticsBootstrap.trackPage(path);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _trackRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _trackRoute(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _trackRoute(previousRoute);
  }

  void _trackRoute(Route<dynamic> route) {
    if (route is! PageRoute<dynamic>) return;
    final path = _normalizePath(route.settings.name);
    if (path == null || path == _lastPath) return;
    _lastPath = path;
    Ga4AnalyticsBootstrap.trackPage(path);
  }

  String? _normalizePath(String? routeName) {
    if (routeName == null || routeName.isEmpty) return '/';
    final uri = Uri.tryParse(routeName);
    if (uri == null) return routeName.startsWith('/') ? routeName : '/$routeName';
    return uri.path.isEmpty ? '/' : uri.path;
  }
}
