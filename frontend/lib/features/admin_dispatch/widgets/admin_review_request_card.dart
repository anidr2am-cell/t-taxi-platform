import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../config/app_config.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/clipboard_writer.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';

String reviewRequestMessage(
  String locale,
  String bookingNumber,
  String googleUrl, {
  String? origin,
}) {
  final l10n = AppLocalizations(locale);
  final baseOrigin = origin ?? (const ['http', 'https'].contains(Uri.base.scheme)
      ? Uri.base.origin : Uri.parse(AppConfig.apiBaseUrl).origin);
  final bookingUrl = Uri.parse(
    '$baseOrigin/booking/lookup',
  ).replace(queryParameters: {'bookingNumber': bookingNumber, 'lang': locale});
  final text = l10n
      .t('admin_review_request_template')
      .replaceAll('{bookingUrl}', bookingUrl.toString());
  final googleLine = googleUrl.isEmpty
      ? ''
      : '${l10n.t('admin_review_request_google_line').replaceAll('{googleUrl}', googleUrl)}\n';
  return text.replaceAll('{googleLine}', googleLine);
}

class AdminReviewRequestCard extends StatefulWidget {
  const AdminReviewRequestCard({
    super.key,
    required this.bookingNumber,
    required this.api,
    this.onChanged,
  });
  final String bookingNumber;
  final AdminDispatchApiService api;
  final VoidCallback? onChanged;
  @override
  State<AdminReviewRequestCard> createState() => _AdminReviewRequestCardState();
}

class _AdminReviewRequestCardState extends State<AdminReviewRequestCard> {
  Map<String, dynamic>? _data;
  String? _locale;
  String _channel = 'KAKAO';
  String? _error;
  bool _busy = false;
  static const _channels = [
    'KAKAO',
    'LINE',
    'WHATSAPP',
    'SMS',
    'EMAIL',
    'OTHER',
  ];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminReviewRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingNumber != widget.bookingNumber) {
      _data = null;
      _locale = null;
      _load();
    }
  }

  Future<void> _load() async {
    final number = widget.bookingNumber;
    try {
      final data = await widget.api.getReviewRequest(number);
      if (!mounted || number != widget.bookingNumber) return;
      setState(() {
        _data = data;
        _locale = data['locale'] as String?;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'admin_review_request_error');
    }
  }

  Future<void> _record(Map<String, dynamic> action) async {
    final data = await widget.api.recordReviewRequest(
      widget.bookingNumber,
      action,
    );
    if (mounted)
      setState(() {
        _data = {...?_data, ...data};
        _error = null;
      });
    widget.onChanged?.call();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _error = 'admin_review_request_error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String message) async {
    try {
      await writeClipboardText(message);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('admin_review_request_copy_failed')),
          ),
        );
      return;
    }
    await _record({'action': 'COPY', 'locale': _locale});
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_review_request_copied'))),
      );
  }

  Future<void> _sent() async {
    final resend = _data?['status'] == 'SENT';
    if (resend) {
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.t('admin_review_request_resend_warning')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.t('admin_review_request_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.t('admin_review_request_mark_sent')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _record({
      'action': 'SENT',
      'locale': _locale,
      'channel': _channel,
      'confirmResend': resend,
    });
  }

  String _channelLabel(String channel) =>
      context.l10n.t('admin_review_channel_${channel.toLowerCase()}');
  String _time(String value) {
    final time = DateTime.tryParse(
      value,
    )?.toUtc().add(const Duration(hours: 7));
    return time == null
        ? ''
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = _data;
    if (data == null)
      return _error == null ? const SizedBox.shrink() : Text(l10n.t(_error!));
    if (data['eligible'] != true) return const SizedBox.shrink();
    final optedOut = data['optedOut'] == true;
    final message = _locale == null
        ? ''
        : reviewRequestMessage(
            _locale!,
            widget.bookingNumber,
            data['googleReviewUrl'] as String? ?? '',
          );
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('admin_review_request_title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n.t(switch (data['status']) {
              'SENT' => 'admin_review_request_sent',
              'COPIED' => 'admin_review_request_copied',
              _ => 'admin_review_request_not_requested',
            }),
          ),
          if (data['sentAt'] != null)
            Text(
              l10n
                  .t('admin_review_request_sent_detail')
                  .replaceAll(
                    '{channel}',
                    _channelLabel(data['channel'] as String? ?? 'OTHER'),
                  )
                  .replaceAll('{time}', _time(data['sentAt'] as String))
                  .replaceAll(
                    '{actor}',
                    '${data['actorName'] ?? data['actorUserId'] ?? ''}',
                  ),
            ),
          const SizedBox(height: AppTokens.spaceMd),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'review_request_language_${widget.bookingNumber}_$_locale',
            ),
            initialValue: _locale,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.t('admin_review_request_locale'),
            ),
            hint: Text(l10n.t('admin_review_request_choose_locale')),
            items: AppLocalizations.supportedLanguages
                .map(
                  (language) => DropdownMenuItem(
                    value: language,
                    child: Text(AppLocalizations.languageNames[language]!),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _locale = value),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SelectableText(message),
          const SizedBox(height: AppTokens.spaceMd),
          Text(l10n.t('admin_review_request_manual_note')),
          const SizedBox(height: AppTokens.spaceMd),
          OutlinedButton.icon(
            onPressed: _busy || optedOut || _locale == null
                ? null
                : () => _run(() => _copy(message)),
            icon: const Icon(Icons.copy),
            label: Text(l10n.t('admin_review_request_copy')),
          ),
          DropdownButtonFormField<String>(
            initialValue: _channel,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.t('admin_review_request_channel'),
            ),
            items: _channels
                .map(
                  (channel) => DropdownMenuItem(
                    value: channel,
                    child: Text(_channelLabel(channel)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _channel = value!),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          OutlinedButton(
            onPressed: _busy || optedOut || _locale == null
                ? null
                : () => _run(_sent),
            child: Text(l10n.t('admin_review_request_mark_sent')),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: optedOut,
            title: Text(l10n.t('admin_review_request_opt_out')),
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => _record({'action': 'OPT_OUT', 'optedOut': value!}),
                  ),
          ),
          if (_error != null)
            Text(
              l10n.t(_error!),
              style: const TextStyle(color: AppTokens.error),
            ),
        ],
      ),
    );
  }
}
