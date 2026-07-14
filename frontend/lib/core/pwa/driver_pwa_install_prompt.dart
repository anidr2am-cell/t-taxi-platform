import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'pwa_install_service.dart';

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
      Navigator.of(context, rootNavigator: true).maybePop();
      _dialogOpen = false;
      _dismissedForThisHost = true;
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
    final l10n = AppLocalizations(Localizations.localeOf(context).languageCode);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DriverPwaInstallDialog(
          service: _service,
          l10n: l10n,
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
    required this.l10n,
    required this.onDismissForSession,
    required this.onSnack,
  });

  final PwaInstallService service;
  final AppLocalizations l10n;
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
      widget.onDismissForSession();
      Navigator.of(context, rootNavigator: true).maybePop();
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
        widget.onDismissForSession();
        Navigator.of(context, rootNavigator: true).pop();
        widget.onSnack(widget.l10n.t('driver_pwa_install_success'));
      case PwaInstallResult.dismissed:
        widget.onDismissForSession();
        Navigator.of(context, rootNavigator: true).pop();
        widget.onSnack(widget.l10n.t('driver_pwa_install_dismissed'));
      case PwaInstallResult.unavailable:
        setState(() => _manualInstallVisible = true);
        widget.onSnack(widget.l10n.t('driver_pwa_install_unavailable'));
      case PwaInstallResult.error:
        setState(() => _manualInstallVisible = true);
        widget.onSnack(widget.l10n.t('driver_pwa_install_error'));
    }
  }

  String get _instructionText {
    if (widget.service.isInAppBrowser) {
      return widget.l10n.t('driver_pwa_install_open_in_chrome');
    }
    if (widget.service.isIos) {
      return widget.l10n.t('driver_pwa_install_ios_steps');
    }
    return widget.l10n.t('driver_pwa_install_manual');
  }

  String get _primaryLabel {
    if (_installing) return widget.l10n.t('driver_pwa_install_now');
    if (_waitingForInstallPrompt && !_manualInstallVisible) {
      return widget.l10n.t('driver_pwa_install_preparing');
    }
    return widget.l10n.t('driver_pwa_install_now');
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
    return AlertDialog(
      icon: Image.asset(
        'assets/images/logo.png',
        width: 56,
        height: 56,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.install_mobile, size: 48),
      ),
      title: Text(widget.l10n.t('driver_pwa_install_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.l10n.t('driver_pwa_install_body')),
            if (_waitingForInstallPrompt && !_manualInstallVisible) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.hourglass_empty, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.l10n.t('driver_pwa_install_preparing'),
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
          child: Text(widget.l10n.t('driver_pwa_install_later')),
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
