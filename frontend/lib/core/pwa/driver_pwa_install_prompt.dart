import 'dart:async';

import 'package:flutter/material.dart';

import 'pwa_install_service.dart';

class _DriverPwaInstallCopy {
  const _DriverPwaInstallCopy._();

  static const title = 'ติดตั้งแอป T-Ride Driver';
  static const body =
      'เพื่อรับงานและใช้งานได้สะดวกยิ่งขึ้น กรุณาติดตั้ง T-Ride Driver ไว้บนหน้าจอหลักของโทรศัพท์';
  static const preparing = 'กำลังเตรียมการติดตั้ง...';
  static const installNow = 'ติดตั้งตอนนี้';
  static const later = 'ไว้ภายหลัง';
  static const manual =
      'หากหน้าต่างติดตั้งไม่แสดง ให้แตะเมนู ⋮ ของ Chrome แล้วเลือก “ติดตั้งแอป” หรือ “เพิ่มลงในหน้าจอหลัก”';
  static const openInChrome =
      'กรุณาเปิดลิงก์นี้ด้วย Google Chrome เพื่อติดตั้งแอป';
  static const ios =
      'แตะปุ่มแชร์ใน Safari จากนั้นเลือก “เพิ่มไปยังหน้าจอโฮม” และแตะ “เพิ่ม”';
  static const dismissed =
      'ยกเลิกการติดตั้งแล้ว คุณสามารถติดตั้งใหม่ได้ภายหลัง';
  static const completeTitle = 'ติดตั้งสำเร็จแล้ว';
  static const completeBody =
      'ติดตั้ง T-Ride Driver เรียบร้อยแล้ว กรุณาปิดเบราว์เซอร์และเปิดแอปจากไอคอนบนหน้าจอหลัก';
  static const manualClose =
      'ติดตั้ง T-Ride Driver เรียบร้อยแล้ว\nกรุณาปิดเบราว์เซอร์นี้ แล้วเปิดแอปจากไอคอน T-Ride Driver บนหน้าจอหลัก';
  static const closeBrowser = 'ปิดเบราว์เซอร์';
  static const ok = 'ตกลง';
}

class DriverPwaInstallPromptHost extends StatefulWidget {
  const DriverPwaInstallPromptHost({
    super.key,
    required this.child,
    this.service,
  });

  final Widget child;
  final PwaInstallService? service;

  @override
  State<DriverPwaInstallPromptHost> createState() =>
      _DriverPwaInstallPromptHostState();
}

class _DriverPwaInstallPromptHostState
    extends State<DriverPwaInstallPromptHost> {
  late final PwaInstallService _service =
      widget.service ?? createPwaInstallService();
  late final bool _ownsService = widget.service == null;
  bool _dismissedForThisHost = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPrompt());
  }

  void _handleServiceChanged() {
    if (!mounted) return;
    if (_dialogOpen && (_service.isStandalone || _service.isInstalled)) {
      _dismissedForThisHost = true;
      return;
    }
    _maybeShowPrompt();
  }

  bool get _shouldShowPrompt {
    return _service.isSupported &&
        !_service.isStandalone &&
        !_service.isInstalled &&
        !_dismissedForThisHost &&
        !_dialogOpen;
  }

  void _maybeShowPrompt() {
    if (!mounted || !_shouldShowPrompt) return;
    _showPrompt();
  }

  Future<void> _showPrompt() async {
    if (!mounted || !_shouldShowPrompt) return;
    _dialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DriverPwaInstallDialog(
          service: _service,
          onDismissForSession: () => _dismissedForThisHost = true,
          onSnack: _showSnack,
        );
      },
    );

    if (mounted) {
      _dialogOpen = false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DriverPwaInstallDialog extends StatefulWidget {
  const _DriverPwaInstallDialog({
    required this.service,
    required this.onDismissForSession,
    required this.onSnack,
  });

  final PwaInstallService service;
  final VoidCallback onDismissForSession;
  final ValueChanged<String> onSnack;

  @override
  State<_DriverPwaInstallDialog> createState() =>
      _DriverPwaInstallDialogState();
}

class _DriverPwaInstallDialogState extends State<_DriverPwaInstallDialog> {
  Timer? _manualInstallTimer;
  bool _manualInstallVisible = false;
  bool _installing = false;
  bool _installCompleted = false;
  bool _installCompletionHandled = false;
  bool _closeAttempted = false;
  bool _manualCloseVisible = false;

  bool get _cannotAutoInstall =>
      widget.service.isIos || widget.service.isInAppBrowser;

  bool get _waitingForInstallPrompt =>
      !_cannotAutoInstall && !widget.service.canPromptInstall;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_handleServiceChanged);
    _manualInstallVisible = _cannotAutoInstall;
    _startInstallAvailabilityTimer();
  }

  void _startInstallAvailabilityTimer() {
    _manualInstallTimer?.cancel();
    if (!_waitingForInstallPrompt) return;
    _manualInstallTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || widget.service.canPromptInstall) return;
      setState(() => _manualInstallVisible = true);
    });
  }

  void _handleServiceChanged() {
    if (!mounted) return;
    if (widget.service.isStandalone || widget.service.isInstalled) {
      unawaited(_handleInstallCompleted());
      return;
    }
    if (widget.service.canPromptInstall) {
      _manualInstallTimer?.cancel();
      setState(() => _manualInstallVisible = false);
      return;
    }
    setState(
      () => _manualInstallVisible = _manualInstallVisible || _cannotAutoInstall,
    );
    _startInstallAvailabilityTimer();
  }

  Future<void> _handleInstall() async {
    if (_installing || !widget.service.canPromptInstall || _cannotAutoInstall) {
      return;
    }

    setState(() => _installing = true);
    final result = await widget.service.promptInstall();
    if (!mounted) return;
    setState(() => _installing = false);

    switch (result) {
      case PwaInstallResult.accepted:
      case PwaInstallResult.alreadyInstalled:
        await _handleInstallCompleted();
      case PwaInstallResult.dismissed:
        widget.onDismissForSession();
        Navigator.of(context, rootNavigator: true).pop();
        widget.onSnack(_DriverPwaInstallCopy.dismissed);
      case PwaInstallResult.unavailable:
        setState(() => _manualInstallVisible = true);
      case PwaInstallResult.error:
        setState(() => _manualInstallVisible = true);
    }
  }

  Future<void> _handleInstallCompleted() async {
    if (_installCompletionHandled) return;
    _installCompletionHandled = true;
    _manualInstallTimer?.cancel();
    widget.onDismissForSession();
    if (!mounted) return;
    setState(() {
      _installing = false;
      _installCompleted = true;
      _manualCloseVisible = false;
    });
    await _tryCloseBrowser();
  }

  Future<void> _tryCloseBrowser({bool force = false}) async {
    if (_closeAttempted && !force) return;
    _closeAttempted = true;
    await widget.service.tryCloseWindow();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || !_installCompleted) return;
    setState(() => _manualCloseVisible = true);
  }

  String get _instructionText {
    if (widget.service.isInAppBrowser) {
      return _DriverPwaInstallCopy.openInChrome;
    }
    if (widget.service.isIos) {
      return _DriverPwaInstallCopy.ios;
    }
    return _DriverPwaInstallCopy.manual;
  }

  String get _primaryLabel {
    if (_installing) return _DriverPwaInstallCopy.installNow;
    if (_waitingForInstallPrompt && !_manualInstallVisible) {
      return _DriverPwaInstallCopy.preparing;
    }
    return _DriverPwaInstallCopy.installNow;
  }

  bool get _primaryEnabled =>
      !_installing && !_cannotAutoInstall && widget.service.canPromptInstall;

  @override
  void dispose() {
    _manualInstallTimer?.cancel();
    widget.service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_installCompleted) {
      return AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 48),
        title: const Text(_DriverPwaInstallCopy.completeTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            _manualCloseVisible
                ? _DriverPwaInstallCopy.manualClose
                : _DriverPwaInstallCopy.completeBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text(_DriverPwaInstallCopy.ok),
          ),
          FilledButton.icon(
            onPressed: () => _tryCloseBrowser(force: true),
            icon: const Icon(Icons.close),
            label: const Text(_DriverPwaInstallCopy.closeBrowser),
          ),
        ],
      );
    }

    return AlertDialog(
      icon: Image.asset(
        'assets/images/logo.png',
        width: 56,
        height: 56,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.install_mobile, size: 48),
      ),
      title: const Text(_DriverPwaInstallCopy.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(_DriverPwaInstallCopy.body),
            if (_waitingForInstallPrompt && !_manualInstallVisible) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.hourglass_empty, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _DriverPwaInstallCopy.preparing,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (_manualInstallVisible || _cannotAutoInstall) ...[
              const SizedBox(height: 12),
              Text(
                _instructionText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing
              ? null
              : () {
                  widget.onDismissForSession();
                  Navigator.of(context, rootNavigator: true).pop();
                },
          child: const Text(_DriverPwaInstallCopy.later),
        ),
        FilledButton.icon(
          onPressed: _primaryEnabled ? _handleInstall : null,
          icon: _installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _waitingForInstallPrompt && !_manualInstallVisible
              ? const Icon(Icons.hourglass_empty)
              : const Icon(Icons.download_for_offline_outlined),
          label: Text(_primaryLabel),
        ),
      ],
    );
  }
}
