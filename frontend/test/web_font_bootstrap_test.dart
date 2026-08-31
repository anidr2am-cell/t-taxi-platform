import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_bootstrap disables external font fallback CDN', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains("fontFallbackBaseUrl: ''"));
    expect(bootstrap, contains("canvasKitBaseUrl: 'canvaskit/'"));
  });

  test('index.html injects custom flutter bootstrap', () {
    final index = File('web/index.html').readAsStringSync();
    expect(index, contains('{{flutter_bootstrap_js}}'));
    expect(index, isNot(contains('src="flutter_bootstrap.js"')));
  });
}
