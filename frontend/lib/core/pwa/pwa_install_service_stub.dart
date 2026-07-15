import 'pwa_install_service_base.dart';

PwaInstallService createPwaInstallService() => StubPwaInstallService();

class StubPwaInstallService extends PwaInstallService {
  @override
  bool get isSupported => false;

  @override
  bool get isStandalone => false;

  @override
  bool get isInstalled => false;

  @override
  bool get canPromptInstall => false;

  @override
  bool get isIos => false;

  @override
  bool get isInAppBrowser => false;

  @override
  Future<PwaInstallResult> promptInstall() async =>
      PwaInstallResult.unavailable;

  @override
  Future<bool> tryCloseWindow() async => false;
}
