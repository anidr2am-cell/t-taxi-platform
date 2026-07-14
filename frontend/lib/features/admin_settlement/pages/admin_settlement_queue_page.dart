import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../settlement/utils/settlement_receipt.dart';
import '../services/admin_settlement_api_service.dart';

class AdminSettlementQueuePage extends StatefulWidget {
  const AdminSettlementQueuePage({super.key, this.api});

  final AdminSettlementApiService? api;

  @override
  State<AdminSettlementQueuePage> createState() =>
      _AdminSettlementQueuePageState();
}

class _AdminSettlementQueuePageState extends State<AdminSettlementQueuePage> {
  late final AdminSettlementApiService _api =
      widget.api ?? const AdminSettlementApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  String? _statusFilter;

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
      final data = await _api.listSettlements(status: _statusFilter);
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppUi.adminFilterBar(
            children: [
              DropdownButton<String?>(
                value: _statusFilter,
                hint: const Text('Status'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                  DropdownMenuItem(
                    value: 'RECEIPT_SUBMITTED',
                    child: Text('Receipt submitted'),
                  ),
                  DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
                  DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
                  DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                ],
                onChanged: (v) {
                  setState(() => _statusFilter = v);
                  _load();
                },
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: _loading
                ? AppUi.loadingState()
                : _error != null
                ? AppUi.errorState(
                    message: _error!,
                    onRetry: _load,
                    retryLabel: context.l10n.t('admin_dispatch_retry'),
                  )
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
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: AppTokens.spaceSm),
                      itemBuilder: (context, index) {
                        final item = Map<String, dynamic>.from(
                          _items[index] as Map,
                        );
                        final status =
                            item['commissionStatus'] as String? ?? '';
                        return AppUi.adminQueueCard(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminSettlementDetailPage(
                                bookingNumber: item['bookingNumber'] as String,
                                api: _api,
                                onChanged: _load,
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      item['driverName'] as String? ?? '',
                                      style: const TextStyle(
                                        color: AppTokens.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (item['dueAt'] != null)
                                      Text(
                                        'Due: ${item['dueAt']}',
                                        style: const TextStyle(
                                          color: AppTokens.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (settlementReceiptPresent(item))
                                      Text(
                                        item['receiptStatus'] as String? ??
                                            'RECEIPT_SUBMITTED',
                                        style: const TextStyle(
                                          color: AppTokens.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${item['commissionAmount']} ${item['currency']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AppUi.statusBadge(
                                    status,
                                    tone: AppUi.toneForCommissionStatus(status),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminSettlementDetailPage extends StatefulWidget {
  const AdminSettlementDetailPage({
    super.key,
    required this.bookingNumber,
    required this.api,
    required this.onChanged,
  });

  final String bookingNumber;
  final AdminSettlementApiService api;
  final VoidCallback onChanged;

  @override
  State<AdminSettlementDetailPage> createState() =>
      _AdminSettlementDetailPageState();
}

class _AdminSettlementDetailPageState extends State<AdminSettlementDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _submitting = false;
  final _reasonController = TextEditingController();
  final _manualNoteController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    _manualNoteController.dispose();
    super.dispose();
  }

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
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  Future<void> _approve() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.api.approve(widget.bookingNumber);
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: context.l10n.t('ui_action_failed'),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    if (_submitting || _reasonController.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.api.reject(
        widget.bookingNumber,
        _reasonController.text.trim(),
      );
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: context.l10n.t('ui_action_failed'),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _manualApprove() async {
    if (_submitting) return;
    _manualNoteController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_settlementText(context, 'manual_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_settlementText(context, 'manual_body')),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                _settlementText(context, 'manual_warning'),
                style: const TextStyle(
                  color: AppTokens.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              TextField(
                controller: _manualNoteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _settlementText(context, 'manual_note_label'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_settlementText(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (_manualNoteController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _settlementText(context, 'manual_note_required'),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(_settlementText(context, 'manual_confirm')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await widget.api.manualApprove(
        widget.bookingNumber,
        _manualNoteController.text.trim(),
      );
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: context.l10n.t('ui_action_failed'),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _viewReceipt() async {
    setState(() => _submitting = true);
    try {
      final receipt = await widget.api.getReceipt(widget.bookingNumber);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transfer slip'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
            child: receipt.contentType.startsWith('image/')
                ? Image.memory(
                    receipt.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('Unable to load transfer slip'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description_outlined, size: 52),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(receipt.filename ?? 'Transfer slip'),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(err, fallback: 'Unable to load transfer slip'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?['commissionStatus'] as String? ?? '';
    final canReview = settlementCanApprove(_detail);
    final hasReceipt = settlementReceiptPresent(_detail);
    final canManualApprove = _detail?['canManualApprove'] == true;
    final approval = _detail?['approval'] is Map
        ? Map<String, dynamic>.from(_detail!['approval'] as Map)
        : <String, dynamic>{};
    final approvalMode = approval['mode'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: 'Retry',
            )
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
                          AppUi.statusBadge(
                            status,
                            tone: AppUi.toneForCommissionStatus(status),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        'Status: $status',
                        style: const TextStyle(fontSize: 18),
                      ),
                      if (_detail?['dueAt'] != null)
                        Text('Due: ${_detail?['dueAt']}'),
                      if (hasReceipt)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppTokens.spaceSm,
                          ),
                          child: Text(
                            'Receipt: ${_detail?['receiptStatus'] ?? 'RECEIPT_SUBMITTED'}',
                          ),
                        ),
                      if (approvalMode != null) ...[
                        const SizedBox(height: AppTokens.spaceSm),
                        AppUi.statusBadge(
                          approvalMode == 'MANUAL_WITHOUT_RECEIPT'
                              ? _settlementText(context, 'manual_badge')
                              : _settlementText(context, 'receipt_verified'),
                          tone: approvalMode == 'MANUAL_WITHOUT_RECEIPT'
                              ? AppStatusTone.warning
                              : AppStatusTone.success,
                        ),
                      ],
                    ],
                  ),
                ),
                if (approvalMode != null) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  AppUi.adminDetailSection(
                    context: context,
                    title: _settlementText(context, 'approval_method'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppUi.summaryRow(
                          label: _settlementText(context, 'approval_method'),
                          value: approvalMode == 'MANUAL_WITHOUT_RECEIPT'
                              ? _settlementText(context, 'manual_badge')
                              : _settlementText(context, 'receipt_verified'),
                        ),
                        if (approval['approvedByUserId'] != null)
                          AppUi.summaryRow(
                            label: _settlementText(context, 'approved_by'),
                            value: '${approval['approvedByUserId']}',
                          ),
                        if (approval['approvedAt'] != null)
                          AppUi.summaryRow(
                            label: _settlementText(context, 'approved_at'),
                            value: '${approval['approvedAt']}',
                          ),
                        if ((approval['note'] as String?)?.isNotEmpty == true)
                          AppUi.summaryRow(
                            label: _settlementText(
                              context,
                              'manual_note_label',
                            ),
                            value: approval['note'] as String,
                          ),
                        if (approval['receiptMissingAtApproval'] == true)
                          AppUi.statusBadge(
                            _settlementText(context, 'receipt_missing'),
                            tone: AppStatusTone.warning,
                          ),
                      ],
                    ),
                  ),
                ],
                if (hasReceipt) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  AppUi.secondaryButton(
                    label: 'View transfer slip',
                    icon: Icons.receipt_long_outlined,
                    onPressed: _submitting ? null : _viewReceipt,
                    fullWidth: true,
                  ),
                ],
                if (canReview) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  AppUi.adminDetailSection(
                    context: context,
                    title: 'Review receipt',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _submitting ? null : _approve,
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                        TextField(
                          controller: _reasonController,
                          decoration: const InputDecoration(
                            labelText: 'Rejection reason',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _submitting ? null : _reject,
                            child: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (canManualApprove) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  AppUi.adminDetailSection(
                    context: context,
                    title: _settlementText(context, 'manual_title'),
                    subtitle: _settlementText(context, 'manual_section_hint'),
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.warning,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _submitting ? null : _manualApprove,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(_settlementText(context, 'manual_button')),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

String _settlementText(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  const values = {
    'en': {
      'manual_button': 'Manual settlement approval',
      'manual_title': 'Manual settlement approval',
      'manual_body':
          'No transfer slip has been uploaded. Have you confirmed the actual deposit or separate settlement?',
      'manual_warning':
          'This settlement will be marked complete. If the driver has no other unresolved settlements, they can receive new calls again.',
      'manual_confirm': 'Confirm approval',
      'manual_note_label': 'Approval reason or confirmation note',
      'manual_note_required': 'Please enter an approval note.',
      'manual_section_hint':
          'Use only after confirming payment outside the transfer slip flow.',
      'manual_badge': 'Manual approval',
      'receipt_verified': 'Receipt verified',
      'approval_method': 'Approval method',
      'approved_by': 'Approved by',
      'approved_at': 'Approved at',
      'receipt_missing': 'No transfer slip',
      'cancel': 'Cancel',
    },
    'ko': {
      'manual_button': '수동 정산 승인',
      'manual_title': '수동 정산 승인',
      'manual_body': '송금증이 업로드되지 않았습니다. 실제 입금 또는 별도 정산이 완료된 것을 확인하셨습니까?',
      'manual_warning':
          '이 정산 건이 완료 처리됩니다. 다른 미정산 건이 없으면 해당 기사님은 다시 신규 콜을 받을 수 있습니다.',
      'manual_confirm': '확인 후 승인',
      'manual_note_label': '승인 사유 또는 확인 내용',
      'manual_note_required': '승인 메모를 입력해 주세요.',
      'manual_section_hint': '송금증 없이 외부 입금 확인이 끝난 경우에만 사용하세요.',
      'manual_badge': '수동 승인',
      'receipt_verified': '송금증 확인',
      'approval_method': '승인 방식',
      'approved_by': '승인 관리자',
      'approved_at': '승인 일시',
      'receipt_missing': '송금증 없음',
      'cancel': '취소',
    },
    'th': {
      'manual_button': 'อนุมัติชำระเงินด้วยตนเอง',
      'manual_title': 'อนุมัติชำระเงินด้วยตนเอง',
      'manual_body':
          'ยังไม่มีการอัปโหลดสลิปโอนเงิน คุณได้ตรวจสอบยอดเงินจริงหรือการชำระแยกแล้วหรือไม่?',
      'manual_warning':
          'รายการชำระนี้จะถูกทำเครื่องหมายว่าเสร็จสิ้น หากคนขับไม่มีรายการค้างชำระอื่น จะสามารถรับงานใหม่ได้อีกครั้ง',
      'manual_confirm': 'ยืนยันและอนุมัติ',
      'manual_note_label': 'เหตุผลหรือบันทึกการยืนยัน',
      'manual_note_required': 'กรุณากรอกบันทึกการอนุมัติ',
      'manual_section_hint': 'ใช้เฉพาะเมื่อยืนยันการชำระเงินนอกขั้นตอนสลิปแล้ว',
      'manual_badge': 'อนุมัติด้วยตนเอง',
      'receipt_verified': 'ตรวจสอบสลิปแล้ว',
      'approval_method': 'วิธีอนุมัติ',
      'approved_by': 'ผู้อนุมัติ',
      'approved_at': 'เวลาอนุมัติ',
      'receipt_missing': 'ไม่มีสลิป',
      'cancel': 'ยกเลิก',
    },
  };
  return values[language]?[key] ?? values['en']![key] ?? key;
}
