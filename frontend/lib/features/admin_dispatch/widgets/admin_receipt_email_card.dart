import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';

class AdminReceiptEmailCard extends StatefulWidget {
  const AdminReceiptEmailCard({
    super.key,
    required this.bookingNumber,
    required this.api,
    this.onChanged,
    this.onPaymentConfirmed,
  });
  final String bookingNumber;
  final AdminDispatchApiService api;
  final VoidCallback? onChanged;
  final VoidCallback? onPaymentConfirmed;
  @override
  State<AdminReceiptEmailCard> createState() => _AdminReceiptEmailCardState();
}

class _AdminReceiptEmailCardState extends State<AdminReceiptEmailCard> {
  final _email = TextEditingController();
  Map<String, dynamic>? _state, _preview;
  String _locale = 'en';
  bool _busy = false;
  bool _confirming = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveInput = false}) async {
    try {
      final d = await widget.api.getReceiptEmailState(widget.bookingNumber);
      if (!mounted) return;
      setState(() {
        _state = d;
        if (!preserveInput) {
          _email.text = d['email'] as String? ?? '';
          _locale = d['locale'] as String? ?? 'en';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'admin_receipt_failed');
    }
  }

  String _errorKey(Object e) {
    if (e is AdminDispatchApiException) {
      if (e.errorCode == 'RECEIPT_EMAIL_INVALID')
        return 'admin_receipt_invalid';
      if (e.errorCode == 'RECEIPT_EMAIL_PREVIEW_CHANGED')
        return 'admin_receipt_changed';
      if (e.errorCode == 'RECEIPT_EMAIL_UNAVAILABLE')
        return 'admin_receipt_unavailable';
      if (e.errorCode?.startsWith('RECEIPT_EMAIL_') == true)
        return 'admin_receipt_blocked';
    }
    return 'admin_receipt_failed';
  }

  Future<void> _makePreview() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'admin_receipt_invalid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final p = await widget.api.previewReceiptEmail(widget.bookingNumber, {
        'email': _email.text.trim(),
        'locale': _locale,
      });
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _error = _errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPayment() async {
    if (_busy || _confirming) return;
    final payment = Map<String, dynamic>.from(_state!['payment'] as Map);
    final l = context.l10n;
    var reason = '';
    setState(() => _confirming = true);
    final confirmedReason = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text(l.t('admin_customer_payment_confirm')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l
                      .t('admin_customer_payment_confirm_body')
                      .replaceAll('{booking}', widget.bookingNumber)
                      .replaceAll(
                        '{amount}',
                        '฿' +
                            NumberFormat('#,##0.##').format(payment['amount']),
                      ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l.t('admin_customer_payment_reason'),
                  ),
                  onChanged: (v) => setDialogState(() => reason = v.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l.t('admin_receipt_cancel')),
            ),
            FilledButton(
              onPressed: reason.isEmpty ? null : () => Navigator.pop(c, reason),
              child: Text(l.t('admin_customer_payment_confirm_action')),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmedReason == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final result = await widget.api
          .confirmCustomerPayment(widget.bookingNumber, {
            'confirmed': true,
            'reason': confirmedReason,
            'expectedAmount': payment['amount'],
            'expectedCurrency': payment['currency'],
          });
      if (!mounted) return;
      setState(() => _state = result);
      widget.onPaymentConfirmed?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('admin_customer_payment_success'))),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e is AdminDispatchApiException &&
                  e.errorCode == 'CUSTOMER_PAYMENT_CHANGED'
              ? 'admin_customer_payment_changed'
              : 'admin_customer_payment_failed',
        );
        await _load(preserveInput: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _confirming) return;
    final l = context.l10n;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.t('admin_receipt_confirm_title')),
        content: Text(
          l
              .t('admin_receipt_confirm_body')
              .replaceAll('{email}', _email.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.t('admin_receipt_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.t('admin_receipt_confirm')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    final preview = _preview;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await widget.api.sendReceiptEmail(widget.bookingNumber, {
        'email': _email.text.trim(),
        'locale': _locale,
        'previewHash': preview!['previewHash'],
        'confirmed': true,
      });
      if (!mounted) return;
      setState(() {
        _state = s;
        _preview = null;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorKey(e);
          _preview = null;
        });
        await _load(preserveInput: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = _state;
    final eligible = state?['eligible'] == true;
    final delivery = state?['delivery'];
    final accepted = delivery is Map && delivery['status'] == 'DELIVERED';
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceMd),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.t('admin_receipt_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(l.t('admin_receipt_intro')),
            if (state?['payment'] is Map) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l.t(
                  state!['payment']['status'] == 'PAID'
                      ? 'admin_customer_payment_paid'
                      : 'admin_customer_payment_unconfirmed',
                ),
              ),
              if (state['payment']['canConfirm'] == true)
                OutlinedButton(
                  onPressed: _busy || _confirming ? null : _confirmPayment,
                  child: Text(l.t('admin_customer_payment_confirm')),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTokens.spaceSm,
                ),
                child: Text(
                  l.t(_error!),
                  style: const TextStyle(color: AppTokens.error),
                ),
              ),
            if (state == null && _error == null)
              const LinearProgressIndicator(),
            if (state != null && !eligible)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                child: Text(
                  l.t(
                    accepted
                        ? 'admin_receipt_accepted'
                        : 'admin_receipt_blocked',
                  ),
                ),
              ),
            if (eligible) ...[
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: _email,
                enabled: !_busy && !_confirming,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l.t('admin_receipt_email'),
                ),
                onChanged: (_) => setState(() {
                  _preview = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              DropdownButtonFormField<String>(
                initialValue: _locale,
                decoration: InputDecoration(
                  labelText: l.t('admin_receipt_locale'),
                ),
                items: AppLocalizations.supportedLanguages
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(AppLocalizations.languageNames[v] ?? v),
                      ),
                    )
                    .toList(),
                onChanged: _busy || _confirming
                    ? null
                    : (v) => setState(() {
                        _locale = v!;
                        _preview = null;
                      }),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              if (state?['configured'] != true)
                Text(l.t('admin_receipt_unavailable')),
              OutlinedButton(
                onPressed: _busy || _confirming ? null : _makePreview,
                child: Text(l.t('admin_receipt_preview')),
              ),
              if (_preview != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(_preview!['subject'] as String? ?? ''),
                SelectableText(_preview!['text'] as String? ?? ''),
                const SizedBox(height: AppTokens.spaceSm),
                FilledButton(
                  onPressed:
                      _busy || _confirming || state?['configured'] != true
                      ? null
                      : _send,
                  child: Text(l.t('admin_receipt_send')),
                ),
              ],
            ],
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
