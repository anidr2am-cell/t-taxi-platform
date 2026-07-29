import 'package:flutter/material.dart';

import '../../../core/storage/secure_token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/driver_application_api.dart';
import '../data/driver_application_models.dart';

class DriverApplicationStatusPage extends StatefulWidget {
  const DriverApplicationStatusPage({
    super.key,
    required this.api,
    this.tokenStorage,
  });

  final DriverApplicationDataSource api;
  final TokenStorage? tokenStorage;

  @override
  State<DriverApplicationStatusPage> createState() =>
      _DriverApplicationStatusPageState();
}

class _DriverApplicationStatusPageState
    extends State<DriverApplicationStatusPage> {
  final _numberController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _loading = true;
  bool _manual = false;
  DriverApplicationStoredInfo? _saved;
  DriverApplicationStatusResult? _status;
  DriverApplicationApiException? _error;

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
    final storage = widget.tokenStorage;
    final saved = storage == null
        ? null
        : await storage.readDriverApplicationInfo();
    if (!mounted) return;

    _saved = saved;
    if (saved == null ||
        saved.applicationNumber.isEmpty ||
        saved.statusToken.isEmpty) {
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
      _status = null;
    });
    try {
      final status = await widget.api.getApplicationStatus(
        applicationNumber: number,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } on DriverApplicationApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _manual = true;
      });
    }
  }

  void _showResubmitComingSoon() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.driverApplicationResubmitComingSoon)),
    );
  }

  void _returnToLogin() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.driverApplicationStatusTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_saved != null && !_manual && !_loading && _error == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('driverApplicationStatusManualToggle'),
                  onPressed: () => setState(() => _manual = true),
                  child: Text(l10n.driverApplicationUseManualLookup),
                ),
              ),
            if (_manual) _manualLookup(l10n),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorState(l10n)
            else if (_status != null)
              _statusCard(_status!, l10n),
          ],
        ),
      ),
    );
  }

  Widget _manualLookup(AppLocalizations l10n) {
    return Card(
      key: const Key('driverApplicationStatusManualForm'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.driverApplicationStatusManual,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('driverApplicationStatusNumberField'),
              controller: _numberController,
              decoration: InputDecoration(
                labelText: l10n.driverApplicationNumberLabelField,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('driverApplicationStatusTokenField'),
              controller: _tokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.driverApplicationStatusToken,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('driverApplicationStatusLookupButton'),
              onPressed: () =>
                  _lookup(_numberController.text, _tokenController.text),
              child: Text(l10n.driverApplicationStatusLookup),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(AppLocalizations l10n) {
    final message = _error?.localizedMessage(l10n) ??
        l10n.driverApplicationStatusFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          key: const Key('driverApplicationStatusError'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () =>
              _lookup(_numberController.text, _tokenController.text),
          child: Text(l10n.retry),
        ),
      ],
    );
  }

  Widget _statusCard(
    DriverApplicationStatusResult status,
    AppLocalizations l10n,
  ) {
    final isApproved = status.status == 'APPROVED';
    final isRejected = status.status == 'REJECTED';
    final isPending = !isApproved && !isRejected;

    return Card(
      key: Key(
        isApproved
            ? 'driverApplicationStatusApproved'
            : isRejected
            ? 'driverApplicationStatusRejected'
            : 'driverApplicationStatusPending',
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.driverApplicationNumberLabel(status.applicationNumber),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (isPending)
              Text(
                l10n.driverApplicationStatusPendingMessage,
                key: const Key('driverApplicationStatusPendingMessage'),
              ),
            if (isApproved)
              Text(
                l10n.driverApplicationStatusApprovedMessage,
                key: const Key('driverApplicationStatusApprovedMessage'),
              ),
            if (isRejected) ...[
              Text(
                l10n.driverApplicationStatusRejectedTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (status.rejectionReason?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  '${l10n.driverApplicationRejectionReason}: ${status.rejectionReason}',
                  key: const Key('driverApplicationRejectionReason'),
                ),
              ],
            ],
            if (status.submittedAt.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(status.submittedAt),
            ],
            const SizedBox(height: 16),
            if (isApproved)
              FilledButton(
                key: const Key('driverApplicationStatusGoToLogin'),
                onPressed: _returnToLogin,
                child: Text(l10n.driverApplicationGoToLogin),
              ),
            if (isRejected)
              OutlinedButton(
                key: const Key('driverApplicationResubmitButton'),
                onPressed: _showResubmitComingSoon,
                child: Text(l10n.driverApplicationResubmit),
              ),
          ],
        ),
      ),
    );
  }
}
