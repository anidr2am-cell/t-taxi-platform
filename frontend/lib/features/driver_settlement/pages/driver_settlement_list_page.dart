import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commission settlements'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('No settlements'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_items[index] as Map);
                          return ListTile(
                            title: Text(item['bookingNumber'] as String? ?? ''),
                            subtitle: Text(
                              '${item['commissionAmount']} ${item['currency']} · ${item['commissionStatus']}',
                            ),
                            trailing: Text(item['dueAt'] as String? ?? ''),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverSettlementDetailPage(
                                  bookingNumber: item['bookingNumber'] as String,
                                  api: _api,
                                ),
                              ),
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
        _error = err.toString();
        _loading = false;
      });
    }
  }

  bool _canUpload(String status) {
    return status == 'PENDING' || status == 'REJECTED' || status == 'OVERDUE';
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
      setState(() => _uploadError = err.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?['commissionStatus'] as String? ?? '';
    final canUpload = _canUpload(status);

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Status: $status', style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Amount: ${_detail?['commissionAmount']} ${_detail?['currency']}'),
                      Text('Due: ${_detail?['dueAt'] ?? '-'}'),
                      if (_detail?['rejectionReason'] != null)
                        Text('Rejection: ${_detail?['rejectionReason']}'),
                      const SizedBox(height: 16),
                      if (canUpload) ...[
                        OutlinedButton(
                          onPressed: _uploading ? null : _pickFile,
                          child: Text(
                            _selectedFilename == null
                                ? 'Select receipt (JPG, PNG, PDF)'
                                : 'Replace selection',
                          ),
                        ),
                        if (_selectedFilename != null) ...[
                          const SizedBox(height: 8),
                          Text('Selected: $_selectedFilename'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _uploading ? null : _uploadSelected,
                            child: Text(_uploading ? 'Uploading...' : 'Upload receipt'),
                          ),
                        ],
                        if (_uploadError != null) ...[
                          const SizedBox(height: 8),
                          Text(_uploadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          OutlinedButton(
                            onPressed: _uploading ? null : _uploadSelected,
                            child: const Text('Retry upload'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}
