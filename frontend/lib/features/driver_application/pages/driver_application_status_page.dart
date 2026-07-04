import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_application_models.dart';
import '../services/driver_application_api_service.dart';
import '../services/driver_application_storage.dart';
import 'driver_application_form_page.dart';

class DriverApplicationStatusPage extends StatefulWidget {
  const DriverApplicationStatusPage({
    super.key,
    this.api,
    this.storage = const DriverApplicationStorage(),
    this.initialReceipt,
  });

  final DriverApplicationApiService? api;
  final DriverApplicationStorage storage;
  final DriverApplicationReceipt? initialReceipt;

  @override
  State<DriverApplicationStatusPage> createState() =>
      _DriverApplicationStatusPageState();
}

class _DriverApplicationStatusPageState
    extends State<DriverApplicationStatusPage> {
  late final DriverApplicationApiService _api =
      widget.api ?? DriverApplicationApiService();
  final _numberController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _loading = true;
  bool _manual = false;
  String? _error;
  DriverApplicationStatusResult? _status;
  DriverApplicationSavedStatus? _saved;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final receipt = widget.initialReceipt;
    if (receipt != null) {
      await widget.storage.save(receipt);
    }
    final saved = await widget.storage.load();
    if (!mounted) return;
    _saved = saved;
    if (saved == null) {
      setState(() {
        _manual = true;
        _loading = false;
      });
      return;
    }
    _numberController.text = saved.applicationNumber;
    _tokenController.text = saved.statusToken;
    await _lookup(saved.applicationNumber, saved.statusToken);
  }

  Future<void> _lookup(String number, String token) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api.getApplicationStatus(
        applicationNumber: number.trim(),
        token: token.trim(),
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_application_status_failed'),
        );
        _loading = false;
      });
    }
  }

  Future<void> _copyNumber() async {
    final number = _status?.applicationNumber ?? _numberController.text.trim();
    if (number.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: number));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('driver_application_number_copied')),
      ),
    );
  }

  Future<void> _clearSavedToken() async {
    await widget.storage.clear();
    if (!mounted) return;
    setState(() {
      _saved = null;
      _manual = true;
      _status = null;
      _numberController.clear();
      _tokenController.clear();
    });
  }

  AppStatusTone _tone(String status) {
    switch (status) {
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
        return AppStatusTone.error;
      default:
        return AppStatusTone.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'APPROVED':
        return context.l10n.t('driver_application_status_approved');
      case 'REJECTED':
        return context.l10n.t('driver_application_status_rejected');
      default:
        return context.l10n.t('driver_application_status_pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_application_status_title'))),
      body: AppUi.centeredContent(
        maxWidth: 720,
        child: ListView(
          padding: AppUi.pagePadding(context),
          children: [
            if (widget.initialReceipt != null)
              AppUi.surfaceCard(
                backgroundColor: AppTokens.successLight,
                child: Text(
                  l10n.t('driver_application_submitted_message'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTokens.success,
                  ),
                ),
              ),
            if (widget.initialReceipt != null)
              const SizedBox(height: AppTokens.spaceMd),
            if (_manual) _manualLookup(l10n),
            if (_saved != null && !_manual)
              TextButton.icon(
                onPressed: () => setState(() => _manual = true),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.t('driver_application_status_manual')),
              ),
            if (_loading)
              AppUi.loadingState(
                message: l10n.t('driver_application_status_loading'),
              )
            else if (_error != null)
              AppUi.errorState(
                message: _error!,
                retryLabel: l10n.t('ui_retry'),
                onRetry: () =>
                    _lookup(_numberController.text, _tokenController.text),
              )
            else if (_status != null)
              _statusCard(_status!, l10n),
          ],
        ),
      ),
    );
  }

  Widget _manualLookup(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.t('driver_application_status_manual'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _numberController,
              decoration: InputDecoration(
                labelText: l10n.t('driver_application_number'),
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.t('driver_application_status_token'),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.primaryButton(
              label: l10n.t('driver_application_status_lookup'),
              icon: Icons.search,
              onPressed: () =>
                  _lookup(_numberController.text, _tokenController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(
    DriverApplicationStatusResult status,
    AppLocalizations l10n,
  ) {
    final isRejected = status.status == 'REJECTED';
    final isApproved = status.status == 'APPROVED';
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isApproved
                      ? l10n.t('driver_application_approved_title')
                      : isRejected
                      ? l10n.t('driver_application_rejected_title')
                      : l10n.t('driver_application_pending_title'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              AppUi.statusBadge(
                _statusLabel(status.status),
                tone: _tone(status.status),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.summaryRow(
            label: l10n.t('driver_application_number'),
            value: status.applicationNumber,
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: l10n.t('driver_application_submitted_at'),
            value: status.submittedAt,
          ),
          if (status.reviewedAt != null)
            AppUi.summaryRow(
              label: l10n.t('driver_application_reviewed_at'),
              value: status.reviewedAt!,
            ),
          if (isRejected && status.rejectionReason != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            AppUi.surfaceCard(
              backgroundColor: AppTokens.errorLight,
              child: Text(
                status.rejectionReason!,
                style: const TextStyle(color: AppTokens.error),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _copyNumber,
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.t('driver_application_copy_number')),
              ),
              if (isApproved)
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/driver'),
                  icon: const Icon(Icons.login),
                  label: Text(l10n.t('driver_application_login_cta')),
                ),
              if (isRejected)
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverApplicationFormPage(
                        api: _api,
                        resubmitApplicationNumber: _numberController.text
                            .trim(),
                        resubmitToken: _tokenController.text.trim(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.t('driver_application_resubmit_cta')),
                ),
              if (isApproved)
                TextButton.icon(
                  onPressed: _clearSavedToken,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.t('driver_application_clear_saved')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
