import 'package:flutter/foundation.dart';

enum PwaInstallResult {
  accepted,
  dismissed,
  unavailable,
  alreadyInstalled,
  error,
}

abstract class PwaInstallService extends ChangeNotifier {
  bool get isSupported;
  bool get isStandalone;
  bool get isInstalled;
  bool get canPromptInstall;
  bool get isIos;
  bool get isInAppBrowser;

  Future<PwaInstallResult> promptInstall();
  Future<bool> tryCloseWindow();
}
