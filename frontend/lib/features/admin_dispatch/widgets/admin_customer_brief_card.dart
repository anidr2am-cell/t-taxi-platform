import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/browser_download.dart';
import '../../../widgets/app_ui.dart';
import '../../admin/widgets/admin_copy_button.dart';
import '../services/admin_dispatch_api_service.dart';
import '../utils/admin_customer_brief.dart';

class AdminCustomerBriefCard extends StatefulWidget {
  const AdminCustomerBriefCard({
    super.key,
    required this.detail,
    required this.api,
    this.copyText,
  });
  final Map<String, dynamic> detail;
  final AdminDispatchApiService api;
  final Future<void> Function(String)? copyText;
  @override
  State<AdminCustomerBriefCard> createState() => _AdminCustomerBriefCardState();
}

class _AdminCustomerBriefCardState extends State<AdminCustomerBriefCard> {
  String? _locale;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>>? _photos;
  final Map<int, Uint8List> _bytes = {};
  bool get _assigned =>
      briefMap(widget.detail['activeAssignment']).isNotEmpty &&
      briefMap(widget.detail['activeAssignment'])['isActive'] != false;
  @override
  void didUpdateWidget(covariant AdminCustomerBriefCard old) {
    super.didUpdateWidget(old);
    if (old.detail['bookingNumber'] != widget.detail['bookingNumber'] ||
        briefMap(old.detail['activeAssignment'])['assignmentId'] !=
            briefMap(widget.detail['activeAssignment'])['assignmentId']) {
      _photos = null;
      _bytes.clear();
      _error = null;
    }
  }

  Future<void> _load() async {
    if (!_assigned || _loading) return;
    final number = briefText(widget.detail['bookingNumber']);
    final assignment = briefMap(
      widget.detail['activeAssignment'],
    )['assignmentId'];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photos = (await widget.api.getCustomerBriefPhotos(
        number,
      )).map(briefMap).toList();
      final bytes = <int, Uint8List>{};
      for (final photo in photos) {
        final id = (photo['fileId'] as num).toInt();
        bytes[id] = await widget.api.getCustomerBriefPhoto(number, id);
      }
      if (!mounted ||
          number != widget.detail['bookingNumber'] ||
          assignment !=
              briefMap(widget.detail['activeAssignment'])['assignmentId'])
        return;
      setState(() {
        _photos = photos;
        _bytes.addAll(bytes);
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = context.l10n.t('admin_customer_brief_error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String t(String k) => l.t('admin_customer_brief_$k');
    final locale =
        _locale ??
        (AppLocalizations.supportedLanguages.contains(l.languageCode)
            ? l.languageCode
            : 'en');
    final text = buildAdminCustomerBrief(widget.detail, locale);
    return AppUi.adminDetailSection(
      context: context,
      title: t('title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_assigned) Text(t('unassigned')),
          DropdownButtonFormField<String>(
            initialValue: locale,
            decoration: InputDecoration(labelText: t('locale')),
            items: AppLocalizations.supportedLanguages
                .map(
                  (code) => DropdownMenuItem(
                    value: code,
                    child: Text(AppLocalizations.languageNames[code]!),
                  ),
                )
                .toList(),
            onChanged: !_assigned ? null : (v) => setState(() => _locale = v),
          ),
          if (_assigned) ...[
            const SizedBox(height: AppTokens.spaceSm),
            SelectableText(text),
          ],
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: [
              if (_assigned)
                AdminCopyButton(
                  text: text,
                  label: t('copy'),
                  copyText: widget.copyText,
                )
              else
                IconButton(
                  onPressed: null,
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: t('copy'),
                ),
              OutlinedButton.icon(
                onPressed: !_assigned
                    ? null
                    : () => downloadBytes(
                        Uint8List.fromList(utf8.encode(text)),
                        '${widget.detail['bookingNumber']}-customer-$locale.txt',
                        'text/plain;charset=utf-8',
                      ),
                icon: const Icon(Icons.download_outlined),
                label: Text(t('text_download')),
              ),
              OutlinedButton.icon(
                onPressed: !_assigned || _loading ? null : _load,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(t('photos')),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_photos?.isEmpty == true) Text(t('no_photos')),
          for (final photo in _photos ?? <Map<String, dynamic>>[]) ...[
            const SizedBox(height: AppTokens.spaceSm),
            if (_bytes[(photo['fileId'] as num).toInt()] != null) ...[
              Image.memory(
                _bytes[(photo['fileId'] as num).toInt()]!,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => Text(t('error')),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final id = (photo['fileId'] as num).toInt();
                  final ext = photo['mimeType'] == 'image/png'
                      ? 'png'
                      : photo['mimeType'] == 'image/webp'
                      ? 'webp'
                      : 'jpg';
                  downloadBytes(
                    _bytes[id]!,
                    '${widget.detail['bookingNumber']}-vehicle-$id.$ext',
                    photo['mimeType'] as String,
                  );
                },
                icon: const Icon(Icons.download_outlined),
                label: Text(t('photo_download')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
