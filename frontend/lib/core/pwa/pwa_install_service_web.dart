import 'dart:async';
import 'dart:js_interop';

import 'pwa_install_service_base.dart';

@JS('tridePwaIsSupported')
external bool _pwaIsSupported();

@JS('tridePwaIsStandalone')
external bool _pwaIsStandalone();

@JS('tridePwaIsInstalled')
external bool _pwaIsInstalled();

@JS('tridePwaCanInstall')
external bool _pwaCanInstall();

@JS('tridePwaIsIos')
external bool _pwaIsIos();

@JS('tridePwaPromptInstall')
external JSPromise<JSString> _pwaPromptInstall();

@JS('tridePwaSubscribe')
external JSNumber _pwaSubscribe(JSFunction listener);

@JS('tridePwaUnsubscribe')
external void _pwaUnsubscribe(JSNumber id);

PwaInstallService createPwaInstallService() => WebPwaInstallService();

class WebPwaInstallService extends PwaInstallService {
  WebPwaInstallService() {
    try {
      _listenerId = _pwaSubscribe(_handlePwaStateChanged.toJS);
    } catch (_) {
      _listenerId = null;
    }
  }

  JSNumber? _listenerId;

  void _handlePwaStateChanged() {
    notifyListeners();
  }

  @override
  bool get isSupported {
    try {
      return _pwaIsSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isStandalone {
    try {
      return _pwaIsStandalone();
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isInstalled {
    try {
      return _pwaIsInstalled();
    } catch (_) {
      return false;
    }
  }

  @override
  bool get canPromptInstall {
    try {
      return _pwaCanInstall();
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isIos {
    try {
      return _pwaIsIos();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PwaInstallResult> promptInstall() async {
    if (isStandalone || isInstalled) return PwaInstallResult.alreadyInstalled;
    if (!isSupported || !canPromptInstall) return PwaInstallResult.unavailable;

    try {
      final raw = (await _pwaPromptInstall().toDart).toDart;
      return switch (raw) {
        'accepted' => PwaInstallResult.accepted,
        'dismissed' => PwaInstallResult.dismissed,
        'alreadyInstalled' => PwaInstallResult.alreadyInstalled,
        'unavailable' => PwaInstallResult.unavailable,
        _ => PwaInstallResult.error,
      };
    } catch (_) {
      return PwaInstallResult.error;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final id = _listenerId;
    if (id != null) {
      try {
        _pwaUnsubscribe(id);
      } catch (_) {
        // Nothing useful to do if the page is unloading or the bridge is gone.
      }
    }
    super.dispose();
  }
}
