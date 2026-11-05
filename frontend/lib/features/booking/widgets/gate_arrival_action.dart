import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../services/gate_arrival_api.dart';

class GateArrivalAction extends StatefulWidget {
  const GateArrivalAction({
    super.key,
    required this.bookingNumber,
    this.guestToken,
    this.customerToken,
    this.api,
  });
  final String bookingNumber;
  final String? guestToken, customerToken;
  final GateArrivalApi? api;
  @override
  State<GateArrivalAction> createState() => _GateArrivalActionState();
}

class _GateArrivalActionState extends State<GateArrivalAction> {
  late final GateArrivalApi _api = widget.api ?? GateArrivalApi();
  Map<String, dynamic>? _status;
  bool _busy = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _request();
    if (Uri.base.queryParameters['arrival'] == 'gate7') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
          );
      });
    }
  }

  @override
  void didUpdateWidget(covariant GateArrivalAction old) {
    super.didUpdateWidget(old);
    if (old.bookingNumber != widget.bookingNumber ||
        old.guestToken != widget.guestToken ||
        old.customerToken != widget.customerToken)
      _request();
  }

  Future<void> _request({bool send = false}) async {
    if (_busy) return;
    final number = widget.bookingNumber;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await _api.request(
        number,
        guestToken: widget.guestToken,
        customerToken: widget.customerToken,
        send: send,
      );
      if (mounted && widget.bookingNumber == number)
        setState(() => _status = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.t('gate_arrival_confirm_title')),
        content: Text(context.l10n.t('gate_arrival_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.t('gate_arrival_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.t('gate_arrival_send')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _request(send: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n.t;
    final sent = _status?['sent'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('gate_arrival_title'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTokens.primary,
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(t(sent ? 'gate_arrival_sent' : 'gate_arrival_intro')),
        if (_status?['notificationRead'] == true) Text(t('gate_arrival_read')),
        if (_failed)
          Text(
            t('gate_arrival_error'),
            style: const TextStyle(color: AppTokens.error),
          ),
        if (!_failed && !sent && !_busy && _status?['available'] != true)
          Text(t('gate_arrival_unavailable')),
        const SizedBox(height: AppTokens.spaceSm),
        if (!sent)
          FilledButton(
            onPressed: !_busy && _status?['available'] == true ? _send : null,
            child: Text(t('gate_arrival_button'), textAlign: TextAlign.center),
          ),
        TextButton(
          onPressed: _busy ? null : () => _request(),
          child: Text(t('gate_arrival_refresh')),
        ),
        TextButton(
          onPressed: () => launchUrl(
            Uri(
              path: '/support',
              queryParameters: {'lang': context.l10n.languageCode},
            ),
          ),
          child: Text(t('gate_arrival_support')),
        ),
      ],
    );
  }
}
