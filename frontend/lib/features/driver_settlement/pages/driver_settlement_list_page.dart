import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../utils/user_facing_error.dart';
import '../services/driver_settlement_api_service.dart';

typedef ReceiptPickResult = ({List<int> bytes, String filename});

typedef ReceiptFilePicker = Future<ReceiptPickResult?> Function();

const _allowedReceiptExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
const _maxReceiptBytes = 10 * 1024 * 1024;

Future<ReceiptPickResult?> defaultReceiptFilePicker() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _allowedReceiptExtensions,
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  final name = file.name.trim();
  if (name.isEmpty) return null;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!_allowedReceiptExtensions.contains(ext)) return null;
  return (bytes: bytes, filename: name);
}

bool isAllowedReceiptFilename(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  return _allowedReceiptExtensions.contains(ext);
}

class DriverSettlementListPage extends StatefulWidget {
  const DriverSettlementListPage({super.key, this.api});

  final DriverSettlementApiService? api;

  @override
  State<DriverSettlementListPage> createState() => _DriverSettlementListPageState();
}

class _DriverSettlementListPageState extends State<DriverSettlementListPage> {
  late final DriverSettlementApiService _api = widget.api ?? const DriverSettlementApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.listSettlements();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  AppStatusTone _settlementTone(String status) {
    switch (status) {
      case 'PAID':
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
      case 'OVERDUE':
        return AppStatusTone.error;
      case 'PENDING':
      case 'RECEIPT_SUBMITTED':
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commission settlements'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
              ? AppUi.errorState(message: _error!, onRetry: _load, retryLabel: 'Retry')
              : _items.isEmpty
                  ? AppUi.emptyState(
                      title: 'No settlements',
                      icon: Icons.receipt_long_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: AppUi.pagePadding(context),
                        itemCount: _items.length,
                        separatorBuilder: (_, index) => const SizedBox(height: AppTokens.spaceSm),
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_items[index] as Map);
                          final status = item['commissionStatus'] as String? ?? '';
                          return AppUi.surfaceCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverSettlementDetailPage(
                                  bookingNumber: item['bookingNumber'] as String,
                                  api: _api,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTokens.primaryLight,
                                    borderRadius: AppTokens.borderRadiusSm,
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_outlined,
                                    color: AppTokens.primary,
                                  ),
                                ),
                                const SizedBox(width: AppTokens.spaceSm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['bookingNumber'] as String? ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item['commissionAmount']} ${item['currency']}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: AppTokens.textPrimary,
                                        ),
                                      ),
                                      if (item['dueAt'] != null)
                                        Text(
                                          l10n.t('driver_settlement_due').replaceAll(
                                            '{date}',
                                            item['dueAt'] as String,
                                          ),
                                          style: const TextStyle(
                                            color: AppTokens.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    AppUi.statusBadge(status, tone: _settlementTone(status)),
                                    const SizedBox(height: 4),
                                    const Icon(Icons.chevron_right, color: AppTokens.textMuted),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class DriverSettlementDetailPage extends StatefulWidget {
  const DriverSettlementDetailPage({
    super.key,
    required this.bookingNumber,
    required this.api,
    this.receiptPicker,
  });

  final String bookingNumber;
  final DriverSettlementApiService api;
  final ReceiptFilePicker? receiptPicker;

  @override
  State<DriverSettlementDetailPage> createState() => _DriverSettlementDetailPageState();
}

class _DriverSettlementDetailPageState extends State<DriverSettlementDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _uploading = false;
  String? _selectedFilename;
  List<int>? _selectedBytes;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.getSettlement(widget.bookingNumber);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  bool _canUpload(String status) {
    return status == 'PENDING' || status == 'REJECTED' || status == 'OVERDUE';
  }

  AppStatusTone _settlementTone(String status) {
    switch (status) {
      case 'PAID':
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
      case 'OVERDUE':
        return AppStatusTone.error;
      case 'PENDING':
      case 'RECEIPT_SUBMITTED':
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  Future<void> _pickFile() async {
    if (_uploading) return;
    final picker = widget.receiptPicker ?? defaultReceiptFilePicker;
    final picked = await picker();
    if (picked == null) return;
    if (!isAllowedReceiptFilename(picked.filename)) {
      setState(() => _uploadError = 'Supported files: JPG, JPEG, PNG, PDF');
      return;
    }
    if (picked.bytes.length > _maxReceiptBytes) {
      setState(() => _uploadError = 'File exceeds maximum size (10 MB)');
      return;
    }
    setState(() {
      _selectedFilename = picked.filename;
      _selectedBytes = picked.bytes;
      _uploadError = null;
    });
  }

  Future<void> _uploadSelected() async {
    if (_uploading || _selectedBytes == null || _selectedFilename == null) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      await widget.api.uploadReceipt(
        widget.bookingNumber,
        _selectedBytes!,
        _selectedFilename!,
      );
      setState(() {
        _selectedFilename = null;
        _selectedBytes = null;
      });
      await _load();
    } catch (err) {
      setState(() => _uploadError = userFacingError(err, fallback: context.l10n.t('ui_action_failed')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _detail?['commissionStatus'] as String? ?? '';
    final canUpload = _canUpload(status);

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
              ? AppUi.errorState(message: _error!, onRetry: _load, retryLabel: 'Retry')
              : ListView(
                  padding: AppUi.pagePadding(context),
                  children: [
                    AppUi.surfaceCard(
                      backgroundColor: AppTokens.primaryLight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_detail?['commissionAmount']} ${_detail?['currency']}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: AppTokens.primaryDark,
                                  ),
                                ),
                              ),
                              AppUi.statusBadge(status, tone: _settlementTone(status)),
                            ],
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          Text('Status: $status', style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 4),
                          Text('Due: ${_detail?['dueAt'] ?? '-'}'),
                          if (_detail?['rejectionReason'] != null) ...[
                            const SizedBox(height: AppTokens.spaceSm),
                            AppUi.summaryRow(
                              label: 'Rejection',
                              value: _detail?['rejectionReason'] as String,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canUpload) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.adminDetailSection(
                        context: context,
                        title: l10n.t('driver_settlement_receipt_upload'),
                        subtitle: l10n.t('driver_settlement_receipt_formats'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppUi.secondaryButton(
                              label: _selectedFilename == null
                                  ? 'Select receipt (JPG, PNG, PDF)'
                                  : 'Replace selection',
                              icon: Icons.upload_file,
                              onPressed: _uploading ? null : _pickFile,
                              fullWidth: true,
                            ),
                            if (_selectedFilename != null) ...[
                              const SizedBox(height: AppTokens.spaceSm),
                              Text('Selected: $_selectedFilename'),
                              const SizedBox(height: AppTokens.spaceSm),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _uploading ? null : _uploadSelected,
                                  child: Text(_uploading ? 'Uploading...' : 'Upload receipt'),
                                ),
                              ),
                            ],
                            if (_uploadError != null) ...[
                              const SizedBox(height: AppTokens.spaceSm),
                              Text(
                                _uploadError!,
                                style: const TextStyle(color: AppTokens.error),
                              ),
                              AppUi.secondaryButton(
                                label: 'Retry upload',
                                icon: Icons.refresh,
                                onPressed: _uploading ? null : _uploadSelected,
                                fullWidth: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
