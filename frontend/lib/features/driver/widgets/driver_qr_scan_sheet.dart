import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/app_localizations.dart';

/// Full-screen QR capture for boarding or dropoff tokens.
class DriverQrScanSheet extends StatefulWidget {
  const DriverQrScanSheet({
    super.key,
    required this.isBoarding,
    required this.onSubmit,
  });

  final bool isBoarding;
  final Future<void> Function(String token) onSubmit;

  @override
  State<DriverQrScanSheet> createState() => _DriverQrScanSheetState();
}

class _DriverQrScanSheetState extends State<DriverQrScanSheet> {
  final _manualController = TextEditingController();
  bool _cameraMode = false;
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
          _error = err.toString();
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(help),
              ),
              const SizedBox(height: 12),
              if (_cameraMode && !_cameraError)
                SizedBox(
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
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('manualQrTokenField'),
                    controller: _manualController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: widget.isBoarding
                          ? l10n.t('driver_qr_boarding_manual_label')
                          : l10n.t('driver_qr_dropoff_manual_label'),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                            _cameraMode = !_cameraMode;
                            _cameraError = false;
                          }),
                      child: Text(
                        _cameraMode
                            ? l10n.t('driver_qr_use_manual')
                            : l10n.t('driver_qr_use_camera'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _submitting || _cameraMode
                            ? null
                            : () => _submit(_manualController.text),
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.t('driver_qr_submit')),
                      ),
                    ),
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

Future<bool?> showDriverQrScanSheet({
  required BuildContext context,
  required bool isBoarding,
  required Future<void> Function(String token) onSubmit,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DriverQrScanSheet(
      isBoarding: isBoarding,
      onSubmit: onSubmit,
    ),
  );
}
