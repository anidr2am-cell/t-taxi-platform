import 'package:flutter/material.dart';

import '../../../core/storage/secure_token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../data/driver_application_models.dart';

class DriverApplicationCompletePage extends StatefulWidget {
  const DriverApplicationCompletePage({
    super.key,
    required this.receipt,
    this.tokenStorage,
  });

  static const lineGroupQrAsset = 'assets/images/driver_line_group_qr.png';

  final DriverApplicationReceipt receipt;
  final TokenStorage? tokenStorage;

  @override
  State<DriverApplicationCompletePage> createState() =>
      _DriverApplicationCompletePageState();
}

class _DriverApplicationCompletePageState
    extends State<DriverApplicationCompletePage> {
  @override
  void initState() {
    super.initState();
    _persistReceipt();
  }

  Future<void> _persistReceipt() async {
    final storage = widget.tokenStorage;
    if (storage == null) return;
    await storage.writeDriverApplicationInfo(
      applicationNumber: widget.receipt.applicationNumber,
      statusToken: widget.receipt.statusToken,
      submittedAt: widget.receipt.submittedAt,
    );
  }

  void _returnToLogin() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.driverApplicationTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.driverApplicationSubmittedMessage,
              key: const Key('driverApplicationSubmittedMessage'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.driverApplicationLineGroupInstruction,
              key: const Key('driverApplicationLineGroupInstruction'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
                child: Image.asset(
                  DriverApplicationCompletePage.lineGroupQrAsset,
                  key: const Key('driverApplicationLineQr'),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 180,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          l10n.driverApplicationLineQrUnavailable,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.driverApplicationNumberLabel(widget.receipt.applicationNumber),
              key: const Key('driverApplicationCompleteNumber'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.driverApplicationNumberStatusHint,
              key: const Key('driverApplicationNumberStatusHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('driverApplicationBackToLogin'),
              onPressed: _returnToLogin,
              child: Text(l10n.driverApplicationBackToLogin),
            ),
          ],
        ),
      ),
    );
  }
}
