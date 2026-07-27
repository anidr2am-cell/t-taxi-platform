import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
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
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    final picked = await (widget.picker ?? pickSettlementReceipt)();
    if (picked == null) return;
    setState(() {
      _file = picked;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.api.uploadReceipt(widget.bookingNumber, file);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = settlementUploadErrorMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = '송금증 업로드 중 알 수 없는 오류가 발생했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text('송금증 업로드', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('JPG, PNG, PDF 파일을 선택해 주세요.'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('pickSettlementReceipt'),
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_file == null ? '파일 선택' : '다른 파일 선택'),
            ),
            if (_file != null) ...[
              const SizedBox(height: 8),
              Text(_file!.filename, key: const Key('selectedReceiptName')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
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
                  : const Text('업로드'),
            ),
          ],
        ),
      ),
    );
  }
}

String settlementUploadErrorMessage(ApiException error) {
  return switch (error.errorCode) {
    'VALIDATION_ERROR' => '입력값을 확인해 주세요. 송금증 파일이 필요합니다.',
    'INVALID_FILE_TYPE' => '지원하지 않는 파일 형식입니다. JPG, PNG, PDF만 업로드할 수 있습니다.',
    'FILE_TOO_LARGE' => '파일 크기가 너무 큽니다. 더 작은 송금증 파일을 선택해 주세요.',
    'SETTLEMENT_NOT_FOUND' => '정산 정보를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
    'RECEIPT_ALREADY_APPROVED' => '이미 승인된 정산은 송금증을 변경할 수 없습니다.',
    _ => switch (error.kind) {
      ApiFailureKind.invalidFileType =>
        '지원하지 않는 파일 형식입니다. JPG, PNG, PDF만 업로드할 수 있습니다.',
      ApiFailureKind.fileTooLarge => '파일 크기가 너무 큽니다. 더 작은 송금증 파일을 선택해 주세요.',
      ApiFailureKind.notFound => '정산 정보를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
      ApiFailureKind.unauthorized => '로그인이 만료되었습니다. 다시 로그인해 주세요.',
      _ => error.userMessage,
    },
  };
}
