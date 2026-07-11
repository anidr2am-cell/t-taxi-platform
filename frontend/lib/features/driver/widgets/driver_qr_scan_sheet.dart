import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';

/// Full-screen QR capture for boarding or dropoff tokens.
class DriverQrScanSheet extends StatefulWidget {
  const DriverQrScanSheet({
    super.key,
    required this.isBoarding,
    required this.onSubmit,
    this.initialCameraMode = false,
  });

  final bool isBoarding;
  final Future<void> Function(String token) onSubmit;
  final bool initialCameraMode;

  @override
  State<DriverQrScanSheet> createState() => _DriverQrScanSheetState();
}

class _DriverQrScanSheetState extends State<DriverQrScanSheet> {
  final _manualController = TextEditingController();
  late bool _cameraMode = widget.initialCameraMode;
  bool _submitting = false;
  String? _error;
  bool _cameraError = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final token = raw.trim();
    if (token.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = userFacingError(
            err,
            fallback: context.l10n.t('ui_action_failed'),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.isBoarding
        ? l10n.t('driver_qr_boarding_title')
        : l10n.t('driver_qr_dropoff_title');
    final help = widget.isBoarding
        ? l10n.t('driver_qr_boarding_help')
        : l10n.t('driver_qr_dropoff_help');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppTokens.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  AppTokens.spaceMd,
                  AppTokens.spaceSm,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                ),
                child: Text(
                  help,
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeChip(
                        label: l10n.t('driver_qr_use_manual'),
                        selected: !_cameraMode,
                        icon: Icons.keyboard,
                        onTap: _submitting
                            ? null
                            : () => setState(() {
                                _cameraMode = false;
                                _cameraError = false;
                              }),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: _ModeChip(
                        label: l10n.t('driver_qr_use_camera'),
                        selected: _cameraMode,
                        icon: Icons.qr_code_scanner,
                        onTap: _submitting
                            ? null
                            : () => setState(() {
                                _cameraMode = true;
                                _cameraError = false;
                              }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              if (_cameraMode && !_cameraError)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                  ),
                  child: ClipRRect(
                    borderRadius: AppTokens.borderRadiusLg,
                    child: SizedBox(
                      height: 220,
                      child: MobileScanner(
                        onDetect: (capture) {
                          if (_submitting) return;
                          for (final barcode in capture.barcodes) {
                            final value = barcode.rawValue?.trim();
                            if (value != null && value.isNotEmpty) {
                              _submit(value);
                              break;
                            }
                          }
                        },
                        errorBuilder: (context, error) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _cameraError = true);
                          });
                          return AppUi.emptyState(
                            title: l10n.t('driver_qr_camera_unavailable'),
                            message: l10n.t('driver_qr_camera_fallback'),
                            icon: Icons.videocam_off_outlined,
                          );
                        },
                      ),
                    ),
                  ),
                )
              else if (_cameraMode && _cameraError)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                  ),
                  child: AppUi.surfaceCard(
                    backgroundColor: AppTokens.warningLight,
                    child: Column(
                      children: [
                        const Icon(
                          Icons.videocam_off_outlined,
                          color: AppTokens.warning,
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          l10n.t('driver_qr_manual_hint'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTokens.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('driver_qr_manual_hint'),
                        style: const TextStyle(
                          color: AppTokens.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      TextField(
                        key: const Key('manualQrTokenField'),
                        controller: _manualController,
                        autofocus: true,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: widget.isBoarding
                              ? l10n.t('driver_qr_boarding_manual_label')
                              : l10n.t('driver_qr_dropoff_manual_label'),
                          helperText: l10n.t('driver_qr_manual_entry'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: AppUi.surfaceCard(
                    backgroundColor: AppTokens.errorLight,
                    padding: const EdgeInsets.all(AppTokens.spaceSm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTokens.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppTokens.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_cameraMode)
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _submitting
                              ? null
                              : () => _submit(_manualController.text),
                          child: _submitting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.t('driver_qr_submit')),
                        ),
                      ),
                    if (_cameraMode && _submitting) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.loadingState(message: l10n.t('driver_qr_submit')),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppTokens.primaryLight : AppTokens.surfaceMuted,
            borderRadius: AppTokens.borderRadiusMd,
            border: Border.all(
              color: selected ? AppTokens.primary : AppTokens.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppTokens.primary : AppTokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: selected
                        ? AppTokens.primaryDark
                        : AppTokens.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showDriverQrScanSheet({
  required BuildContext context,
  required bool isBoarding,
  required Future<void> Function(String token) onSubmit,
  bool initialCameraMode = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DriverQrScanSheet(
      isBoarding: isBoarding,
      onSubmit: onSubmit,
      initialCameraMode: initialCameraMode,
    ),
  );
}
