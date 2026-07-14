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
  bool _installing = false;

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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> handleInstall() async {
              if (_installing) return;
              setDialogState(() => _installing = true);
              final result = await _service.promptInstall();
              if (!context.mounted) return;
              setDialogState(() => _installing = false);

              switch (result) {
                case PwaInstallResult.accepted:
                case PwaInstallResult.alreadyInstalled:
                  _dismissedForThisHost = true;
                  Navigator.of(context, rootNavigator: true).pop();
                  _showSnack(l10n.t('driver_pwa_install_success'));
                case PwaInstallResult.dismissed:
                  _dismissedForThisHost = true;
                  Navigator.of(context, rootNavigator: true).pop();
                  _showSnack(l10n.t('driver_pwa_install_dismissed'));
                case PwaInstallResult.unavailable:
                  _showSnack(l10n.t('driver_pwa_install_unavailable'));
                case PwaInstallResult.error:
                  _showSnack(l10n.t('driver_pwa_install_error'));
              }
            }

            return AlertDialog(
              icon: Image.asset(
                'assets/images/logo.png',
                width: 56,
                height: 56,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.install_mobile, size: 48),
              ),
              title: Text(l10n.t('driver_pwa_install_title')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.t('driver_pwa_install_body')),
                    const SizedBox(height: 12),
                    if (!_service.canPromptInstall || _service.isIos)
                      Text(
                        _service.isIos
                            ? l10n.t('driver_pwa_install_ios_steps')
                            : l10n.t('driver_pwa_install_manual'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _installing
                      ? null
                      : () {
                          _dismissedForThisHost = true;
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                  child: Text(l10n.t('driver_pwa_install_later')),
                ),
                FilledButton.icon(
                  onPressed: _installing ? null : handleInstall,
                  icon: _installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline_outlined),
                  label: Text(l10n.t('driver_pwa_install_now')),
                ),
              ],
            );
          },
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
