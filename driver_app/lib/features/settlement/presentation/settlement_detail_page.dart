import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
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
    final l10n = AppLocalizations.of(context);
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
                      Text(
                        _error!.localizedMessage(l10n),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: Text(l10n.retry),
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
    final l10n = AppLocalizations.of(context);
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
              text: l10n.completeSettlementForNewCalls,
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
                          l10n.settlementStatusLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Chip(label: Text(status.localizedLabel(l10n))),
                    ],
                  ),
                  _row(
                    l10n.companyCommission,
                    formatSettlementMoneyLocalized(
                      l10n,
                      detail.companyCommissionAmount ?? detail.commissionAmount,
                      detail.companyCommissionCurrency ?? detail.currency,
                    ),
                  ),
                  _row(
                    l10n.customerPaymentTotal,
                    formatSettlementMoneyLocalized(
                      l10n,
                      detail.customerPaymentAmount ??
                          detail.customerTotalAmount,
                      detail.customerPaymentCurrency ??
                          detail.customerTotalCurrency ??
                          detail.currency,
                    ),
                  ),
                  _row(
                    l10n.driverExpectedIncome,
                    formatSettlementMoneyLocalized(
                      l10n,
                      detail.driverExpectedIncomeAmount,
                      detail.driverExpectedIncomeCurrency ?? detail.currency,
                    ),
                  ),
                  _row(
                    l10n.receiptStatusRow(detail.receiptStatus ?? 'NONE'),
                    detail.receiptStatus ?? 'NONE',
                  ),
                  if (detail.dueAt != null)
                    _row(l10n.dueDateLabel, detail.dueAt!),
                  if (detail.rejectionReason != null)
                    _row(l10n.rejectionReasonLabel, detail.rejectionReason!),
                  if (detail.approvalMode == 'MANUAL_WITHOUT_RECEIPT')
                    _row(l10n.approvalMethodManual, l10n.approvalMethodManual),
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
              title: l10n.submittedReceiptTitle,
              future: receiptBytes!,
              emptyText: l10n.receiptFileLoadFailed,
              downloadedText: l10n.fileDownloaded,
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
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('settlementPaymentInstructions'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.depositInstructionsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _row(l10n.bankLabel, instructions.bankName),
            _row(l10n.accountHolderLabel, instructions.accountName),
            _row(l10n.accountNumberLabel, instructions.accountNumber),
            _row('PromptPay', instructions.promptPayNumber),
            if (qrBytes != null)
              _BytesPreview(
                title: 'PromptPay QR',
                future: qrBytes!,
                emptyText: l10n.qrImageLoadFailed,
                downloadedText: l10n.fileDownloaded,
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
    required this.downloadedText,
  });

  final String title;
  final Future<List<int>> future;
  final String emptyText;
  final String downloadedText;

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
                    children: [
                      const Icon(Icons.description_outlined),
                      const SizedBox(width: 8),
                      Text(downloadedText),
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
    final l10n = AppLocalizations.of(context);
    if (status.canUpload) {
      return FilledButton.icon(
        key: const Key('uploadReceiptButton'),
        onPressed: onUpload,
        icon: const Icon(Icons.upload_file),
        label: Text(
          status.code == SettlementStatusCode.rejected
              ? l10n.receiptReupload
              : l10n.receiptUpload,
        ),
      );
    }
    if (status.code == SettlementStatusCode.receiptSubmitted) {
      return OutlinedButton.icon(
        key: const Key('resubmitReceiptButton'),
        onPressed: onUpload,
        icon: const Icon(Icons.pending_actions),
        label: Text(l10n.receiptPendingResubmit),
      );
    }
    return Center(
      child: Text(
        status.code == SettlementStatusCode.approved ||
                status.code == SettlementStatusCode.waived
            ? l10n.settlementCompleted
            : l10n.noFurtherActionRequired,
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
