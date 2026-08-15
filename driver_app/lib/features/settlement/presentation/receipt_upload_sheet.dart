import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/idempotency_key.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/settlement_api.dart';
import '../data/settlement_models.dart';

typedef SettlementReceiptPicker = Future<SettlementUploadFile?> Function();

Future<SettlementUploadFile?> pickSettlementReceipt() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return SettlementUploadFile(filename: file.name, bytes: bytes);
}

Future<bool?> showReceiptUploadSheet({
  required BuildContext context,
  required SettlementDataSource api,
  required String bookingNumber,
  SettlementReceiptPicker? picker,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ReceiptUploadSheet(
      api: api,
      bookingNumber: bookingNumber,
      picker: picker,
    ),
  );
}

class ReceiptUploadSheet extends StatefulWidget {
  const ReceiptUploadSheet({
    super.key,
    required this.api,
    required this.bookingNumber,
    this.picker,
  });

  final SettlementDataSource api;
  final String bookingNumber;
  final SettlementReceiptPicker? picker;

  @override
  State<ReceiptUploadSheet> createState() => _ReceiptUploadSheetState();
}

class _ReceiptUploadSheetState extends State<ReceiptUploadSheet> {
  SettlementUploadFile? _file;
  String? _idempotencyKey;
  bool _uploading = false;
  ApiException? _error;

  Future<void> _pick() async {
    final picked = await (widget.picker ?? pickSettlementReceipt)();
    if (picked == null) return;
    setState(() {
      _file = picked;
      _idempotencyKey = generateIdempotencyKey();
      _error = null;
    });
  }

  Future<void> _upload() async {
    final file = _file;
    final idempotencyKey = _idempotencyKey;
    if (file == null || idempotencyKey == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.api.uploadReceipt(
        widget.bookingNumber,
        file,
        idempotencyKey: idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = error;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = const ApiException(ApiFailureKind.unknown);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final errorMessage = _error == null
        ? null
        : _error!.errorCode != null ||
              _error!.kind == ApiFailureKind.invalidFileType ||
              _error!.kind == ApiFailureKind.fileTooLarge ||
              _error!.kind == ApiFailureKind.notFound
        ? settlementUploadErrorMessage(l10n, _error!)
        : _error!.localizedMessage(l10n);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.receiptUploadTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.receiptFileTypesHint),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('pickSettlementReceipt'),
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _file == null ? l10n.selectFile : l10n.selectDifferentFile,
              ),
            ),
            if (_file != null) ...[
              const SizedBox(height: 8),
              Text(_file!.filename, key: const Key('selectedReceiptName')),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage,
                key: const Key('receiptUploadError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('submitSettlementReceipt'),
              onPressed: _uploading || _file == null ? null : _upload,
              child: _uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.upload),
            ),
          ],
        ),
      ),
    );
  }
}
