import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/settlement_api.dart';
import '../data/settlement_models.dart';
import 'receipt_upload_sheet.dart';

class SettlementDetailPage extends StatefulWidget {
  const SettlementDetailPage({
    super.key,
    required this.api,
    required this.bookingNumber,
    required this.onUnauthorized,
    this.receiptPicker,
  });

  final SettlementDataSource api;
  final String bookingNumber;
  final Future<void> Function() onUnauthorized;
  final SettlementReceiptPicker? receiptPicker;

  @override
  State<SettlementDetailPage> createState() => _SettlementDetailPageState();
}

class _SettlementDetailPageState extends State<SettlementDetailPage> {
  SettlementItem? _detail;
  ApiException? _error;
  bool _loading = true;
  bool _changed = false;
  Future<List<int>>? _receiptBytes;
  Future<List<int>>? _qrBytes;

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
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _receiptBytes = detail.receiptUrl == null
            ? null
            : widget.api.downloadReceipt(detail.receiptUrl!);
        _qrBytes = detail.paymentInstructions.promptPayQrImageUrl.isEmpty
            ? null
            : widget.api.downloadReceipt(
                detail.paymentInstructions.promptPayQrImageUrl,
              );
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _loading = false;
      });
    }
  }

  Future<void> _upload() async {
    final uploaded = await showReceiptUploadSheet(
      context: context,
      api: widget.api,
      bookingNumber: widget.bookingNumber,
      picker: widget.receiptPicker,
    );
    if (uploaded == true && mounted) {
      _changed = true;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.bookingNumber),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: _loading
            ? const Center(
                key: Key('settlementDetailLoading'),
                child: CircularProgressIndicator(),
              )
            : _error != null
            ? Center(
                key: const Key('settlementDetailError'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!.userMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              )
            : _SettlementDetailBody(
                detail: _detail!,
                receiptBytes: _receiptBytes,
                qrBytes: _qrBytes,
                onUpload: _upload,
              ),
      ),
    );
  }
}

class _SettlementDetailBody extends StatelessWidget {
  const _SettlementDetailBody({
    required this.detail,
    required this.receiptBytes,
    required this.qrBytes,
    required this.onUpload,
  });

  final SettlementItem detail;
  final Future<List<int>>? receiptBytes;
  final Future<List<int>>? qrBytes;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final status = detail.commissionStatus;
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        key: const Key('settlementDetailContent'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (detail.blocksNewCalls)
            _WarningBanner(
              key: const Key('settlementBlockingBanner'),
              text: '이 정산을 완료해야 새 콜을 받을 수 있습니다.',
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '정산 상태',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Chip(label: Text(status.label)),
                    ],
                  ),
                  _row(
                    '회사 커미션',
                    formatSettlementMoney(
                      detail.companyCommissionAmount ?? detail.commissionAmount,
                      detail.companyCommissionCurrency ?? detail.currency,
                    ),
                  ),
                  _row(
                    '고객 결제 총액',
                    formatSettlementMoney(
                      detail.customerPaymentAmount ??
                          detail.customerTotalAmount,
                      detail.customerPaymentCurrency ??
                          detail.customerTotalCurrency ??
                          detail.currency,
                    ),
                  ),
                  _row(
                    '기사 예상수입',
                    formatSettlementMoney(
                      detail.driverExpectedIncomeAmount,
                      detail.driverExpectedIncomeCurrency ?? detail.currency,
                    ),
                  ),
                  _row('송금증 상태', detail.receiptStatus ?? 'NONE'),
                  if (detail.dueAt != null) _row('마감', detail.dueAt!),
                  if (detail.rejectionReason != null)
                    _row('반려 사유', detail.rejectionReason!),
                  if (detail.approvalMode == 'MANUAL_WITHOUT_RECEIPT')
                    _row('승인 방식', '관리자 수동 승인'),
                ],
              ),
            ),
          ),
          if (detail.paymentInstructions.hasAny)
            _PaymentCard(
              instructions: detail.paymentInstructions,
              qrBytes: qrBytes,
            ),
          if (receiptBytes != null)
            _BytesPreview(
              title: '제출한 송금증',
              future: receiptBytes!,
              emptyText: '송금증 파일을 불러올 수 없습니다.',
            ),
          const SizedBox(height: 12),
          _ActionSection(status: status, onUpload: onUpload),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.instructions, required this.qrBytes});

  final PaymentInstructions instructions;
  final Future<List<int>>? qrBytes;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('settlementPaymentInstructions'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('입금 안내', style: Theme.of(context).textTheme.titleMedium),
            _row('은행', instructions.bankName),
            _row('예금주', instructions.accountName),
            _row('계좌번호', instructions.accountNumber),
            _row('PromptPay', instructions.promptPayNumber),
            if (qrBytes != null)
              _BytesPreview(
                title: 'PromptPay QR',
                future: qrBytes!,
                emptyText: 'QR 이미지를 불러올 수 없습니다.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text('$label: $value'),
    );
  }
}

class _BytesPreview extends StatelessWidget {
  const _BytesPreview({
    required this.title,
    required this.future,
    required this.emptyText,
  });

  final String title;
  final Future<List<int>> future;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<int>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final bytes = snapshot.data;
                if (bytes == null || bytes.isEmpty) return Text(emptyText);
                return Image.memory(
                  Uint8List.fromList(bytes),
                  key: Key('bytesPreview-$title'),
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Row(
                    children: const [
                      Icon(Icons.description_outlined),
                      SizedBox(width: 8),
                      Text('파일을 다운로드했습니다.'),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.status, required this.onUpload});

  final SettlementStatus status;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    if (status.canUpload) {
      return FilledButton.icon(
        key: const Key('uploadReceiptButton'),
        onPressed: onUpload,
        icon: const Icon(Icons.upload_file),
        label: Text(
          status.code == SettlementStatusCode.rejected ? '송금증 재업로드' : '송금증 업로드',
        ),
      );
    }
    if (status.code == SettlementStatusCode.receiptSubmitted) {
      return OutlinedButton.icon(
        key: const Key('resubmitReceiptButton'),
        onPressed: onUpload,
        icon: const Icon(Icons.pending_actions),
        label: const Text('승인 대기 중 · 다시 제출'),
      );
    }
    return Center(
      child: Text(
        status.code == SettlementStatusCode.approved ||
                status.code == SettlementStatusCode.waived
            ? '정산 처리가 완료되었습니다.'
            : '추가 작업이 필요하지 않습니다.',
        key: const Key('settlementNoAction'),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: colors.onErrorContainer),
        title: Text(text, style: TextStyle(color: colors.onErrorContainer)),
      ),
    );
  }
}
