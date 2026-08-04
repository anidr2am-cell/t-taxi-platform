import 'package:flutter/material.dart';

import '../../booking/utils/booking_status_display.dart';
import '../../booking/utils/review_tags.dart';
import '../../driver/utils/driver_backend_datetime.dart';
import '../../booking/models/country_option.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';
import '../../admin_settlement/services/admin_settlement_api_service.dart';
import '../../settlement/utils/settlement_receipt.dart';
import '../widgets/assign_driver_dialog.dart';
import '../widgets/recommend_drivers_dialog.dart';
import '../widgets/unassign_driver_dialog.dart';
import '../utils/admin_operations_ux.dart';

class AdminBookingDetailPage extends StatefulWidget {
  final String bookingNumber;
  final AdminDispatchApiService api;
  final AdminSettlementApiService settlementApi;
  final VoidCallback onChanged;

  const AdminBookingDetailPage({
    super.key,
    required this.bookingNumber,
    required this.api,
    this.settlementApi = const AdminSettlementApiService(),
    required this.onChanged,
  });

  @override
  State<AdminBookingDetailPage> createState() => _AdminBookingDetailPageState();
}

class _AdminBookingDetailPageState extends State<AdminBookingDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _settlement;
  String? _settlementError;
  bool _submitting = false;
  final _noteController = TextEditingController();
  final _manualSettlementNoteController = TextEditingController();
  final _noShowPenaltyAmountController = TextEditingController();
  final _noShowReasonController = TextEditingController();
  final _noShowMemoController = TextEditingController();
  final _tripSectionKey = GlobalKey();
  final _assignmentSectionKey = GlobalKey();
  final _operationsSummaryKey = GlobalKey();
  final _pricingSectionKey = GlobalKey();
  final _reviewSectionKey = GlobalKey();
  final _activitySectionKey = GlobalKey();
  List<Map<String, dynamic>> _notes = [];
  String? _notesError;
  bool _addingNote = false;

  @override
  void dispose() {
    _noteController.dispose();
    _manualSettlementNoteController.dispose();
    _noShowPenaltyAmountController.dispose();
    _noShowReasonController.dispose();
    _noShowMemoController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l10n = AppLocalizations('en');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.getBookingDetail(widget.bookingNumber);
      List<Map<String, dynamic>> notes = [];
      String? notesError;
      try {
        final response = await widget.api.listBookingNotes(
          widget.bookingNumber,
        );
        notes = (response['items'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } catch (err) {
        notesError = userFacingError(
          err,
          fallback: l10n.t('admin_notes_load_failed'),
        );
      }
      Map<String, dynamic>? settlement;
      String? settlementError;
      if (_shouldLoadSettlementDetail(detail)) {
        try {
          settlement = await widget.settlementApi.getSettlement(
            widget.bookingNumber,
          );
        } catch (err) {
          if (!mounted) return;
          settlementError = userFacingError(
            err,
            fallback: context.l10n.t('ui_load_failed'),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _settlement = settlement;
        _settlementError = settlementError;
        _notes = notes;
        _notesError = notesError;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || text.length > 1000 || _addingNote) return;
    setState(() {
      _addingNote = true;
      _notesError = null;
    });
    try {
      final note = await widget.api.addBookingNote(widget.bookingNumber, text);
      if (!mounted) return;
      setState(() {
        _notes.add(note);
        _noteController.clear();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _notesError = userFacingError(
          err,
          fallback: context.l10n.t('admin_notes_add_failed'),
        );
      });
    } finally {
      if (mounted) setState(() => _addingNote = false);
    }
  }

  List<String> _allowedActions() {
    final actions = _detail?['allowedActions'] as List<dynamic>? ?? [];
    return actions.map((e) => e as String).toList();
  }

  bool _hasActiveAssignment(Map<String, dynamic> detail) {
    final assignment = detail['activeAssignment'];
    return assignment is Map && assignment.isNotEmpty;
  }

  bool _canUnassignDriver(Map<String, dynamic>? detail) {
    if (detail == null) return false;
    if (_allowedActions().contains('UNASSIGN_DRIVER')) return true;
    return detail['status'] == 'DRIVER_ASSIGNED' &&
        _hasActiveAssignment(detail);
  }

  String _unassignDriverErrorMessage(Object err, AppLocalizations l10n) {
    if (err is AdminDispatchApiException) {
      switch (err.errorCode) {
        case 'INVALID_STATUS_FOR_UNASSIGN':
          return l10n.t('admin_dispatch_unassign_error_invalid_status');
        case 'NO_ACTIVE_ASSIGNMENT':
          return l10n.t('admin_dispatch_unassign_error_no_assignment');
        case 'VALIDATION_ERROR':
          return validationErrorMessage(err, languageCode: l10n.languageCode) ??
              l10n.t('admin_dispatch_unassign_error_validation');
        default:
          break;
      }
    }
    return userFacingError(
      err,
      fallback: l10n.t('admin_dispatch_unassign_failed'),
    );
  }

  bool get _hasTransferSlip => settlementReceiptPresent(_settlement);

  bool get _canConfirmSettlement =>
      _detail?['status'] == 'SETTLEMENT_PENDING' &&
      _settlement?['canApprove'] == true;

  bool get _canManualApproveSettlement =>
      _detail?['status'] == 'SETTLEMENT_PENDING' &&
      _settlement?['canManualApprove'] == true;

  bool _shouldLoadSettlementDetail(Map<String, dynamic> detail) {
    final status = detail['status'] as String?;
    final commissionStatus = detail['commissionStatus'] as String?;
    return status == 'SETTLEMENT_PENDING' ||
        commissionStatus == 'DUE' ||
        commissionStatus == 'OVERDUE' ||
        commissionStatus == 'PAID';
  }

  bool _settlementVisible(Map<String, dynamic> detail) {
    final status = detail['status'] as String?;
    final commissionStatus =
        (_settlement?['commissionStatus'] as String?) ??
        detail['commissionStatus'] as String?;
    final receiptStatus = _settlement?['receiptStatus'] as String?;
    return status == 'SETTLEMENT_PENDING' ||
        commissionStatus == 'DUE' ||
        commissionStatus == 'OVERDUE' ||
        commissionStatus == 'PAID' ||
        receiptStatus != null ||
        _settlement != null ||
        _settlementError != null;
  }

  bool _hasSettlementStateMismatch(Map<String, dynamic> detail) {
    final status = detail['status'] as String?;
    final commissionStatus =
        (_settlement?['commissionStatus'] as String?) ??
        detail['commissionStatus'] as String?;
    return status == 'COMPLETED' &&
        (commissionStatus == 'DUE' ||
            commissionStatus == 'OVERDUE' ||
            commissionStatus == 'PENDING');
  }

  static const Set<String> _noShowBlockedStatuses = {
    'PICKED_UP',
    'SETTLEMENT_PENDING',
    'COMPLETED',
    'CANCELLED',
    'NO_SHOW',
  };

  static const Set<String> _noShowPreAssignmentStatuses = {
    'PENDING',
    'OPEN',
    'CONFIRMED',
  };

  static const Set<String> _noShowAssignedStatuses = {
    'DRIVER_ASSIGNED',
    'ON_ROUTE',
    'DRIVER_ARRIVED',
  };

  Map<String, dynamic>? _noShowPenalty(Map<String, dynamic> detail) {
    final penalty = detail['noShowPenalty'];
    if (penalty is! Map) return null;
    return Map<String, dynamic>.from(penalty);
  }

  bool _hasNoShowPenalty(Map<String, dynamic> detail) =>
      _noShowPenalty(detail) != null;

  bool _shouldShowNoShowButton(Map<String, dynamic> detail) {
    if (_hasNoShowPenalty(detail)) return false;
    final status = detail['status'] as String?;
    if (status == null || status.isEmpty) return false;
    if (_noShowBlockedStatuses.contains(status)) return false;
    return _noShowPreAssignmentStatuses.contains(status) ||
        _noShowAssignedStatuses.contains(status);
  }

  bool _isNoShowActionEnabled(Map<String, dynamic> detail) {
    final status = detail['status'] as String?;
    if (status == null || status.isEmpty) return false;
    return _noShowAssignedStatuses.contains(status);
  }

  Widget _noShowActionButton(Map<String, dynamic> detail) {
    final enabled = _isNoShowActionEnabled(detail) && !_submitting;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        style: enabled
            ? OutlinedButton.styleFrom(
                foregroundColor: AppTokens.warning,
                side: const BorderSide(color: AppTokens.warning),
              )
            : null,
        onPressed: enabled ? _processNoShow : null,
        icon: const Icon(Icons.person_off_outlined),
        label: Text(_noShowText(context, 'button')),
      ),
    );
  }

  String _noShowErrorMessage(Object err, AppLocalizations l10n) {
    if (err is AdminDispatchApiException) {
      switch (err.errorCode) {
        case 'BOOKING_NO_SHOW_ALREADY_PROCESSED':
          return _noShowText(context, 'error_already_processed');
        case 'INVALID_STATUS_TRANSITION':
          return _noShowText(context, 'error_invalid_status');
        case 'FORBIDDEN':
          return _noShowText(context, 'error_forbidden');
        case 'VALIDATION_ERROR':
          return validationErrorMessage(err, languageCode: l10n.languageCode) ??
              _noShowText(context, 'error_validation');
        default:
          break;
      }
    }
    return userFacingError(
      err,
      fallback: _noShowText(context, 'error_action_failed'),
    );
  }

  Future<void> _processNoShow() async {
    if (_submitting || _detail == null) return;
    _noShowPenaltyAmountController.clear();
    _noShowReasonController.clear();
    _noShowMemoController.clear();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final penaltyText = _noShowPenaltyAmountController.text.trim();
            final reasonText = _noShowReasonController.text.trim();
            final memoText = _noShowMemoController.text.trim();
            final penaltyAmount = num.tryParse(penaltyText);
            final canSubmit =
                penaltyAmount != null &&
                penaltyAmount > 0 &&
                reasonText.isNotEmpty &&
                reasonText.length <= 1000 &&
                memoText.length <= 500;

            return AlertDialog(
              title: Text(_noShowText(context, 'title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_noShowText(context, 'body')),
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      _noShowText(context, 'warning'),
                      style: const TextStyle(
                        color: AppTokens.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    TextField(
                      controller: _noShowPenaltyAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _noShowText(context, 'penalty_label'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    TextField(
                      controller: _noShowReasonController,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: _noShowText(context, 'reason_label'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    TextField(
                      controller: _noShowMemoController,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: _noShowText(context, 'memo_label'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_noShowText(context, 'cancel')),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Text(_noShowText(context, 'confirm')),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final penaltyAmount = num.parse(_noShowPenaltyAmountController.text.trim());
    final reason = _noShowReasonController.text.trim();
    final memo = _noShowMemoController.text.trim();

    setState(() => _submitting = true);
    try {
      await widget.api.processNoShow(
        widget.bookingNumber,
        penaltyAmount: penaltyAmount,
        reason: reason,
        memo: memo.isEmpty ? null : memo,
      );
      widget.onChanged();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_noShowText(context, 'success'))),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_noShowErrorMessage(err, context.l10n))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _retrySettlement() async {
    setState(() {
      _submitting = true;
      _settlementError = null;
    });
    try {
      final settlement = await widget.settlementApi.getSettlement(
        widget.bookingNumber,
      );
      if (!mounted) return;
      setState(() => _settlement = settlement);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _settlementError = userFacingError(
          err,
          fallback: context.l10n.t('admin_detail_settlement_load_failed'),
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _viewTransferSlip() async {
    final l10n = context.l10n;
    setState(() => _submitting = true);
    try {
      final receipt = await widget.settlementApi.getReceipt(
        widget.bookingNumber,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('admin_settlement_transfer_slip')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
            child: receipt.contentType.startsWith('image/')
                ? Image.memory(
                    receipt.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        Text(l10n.t('admin_settlement_slip_load_failed')),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description_outlined, size: 52),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        receipt.filename ??
                            l10n.t('admin_settlement_transfer_slip'),
                      ),
                      Text(receipt.contentType),
                      Text('${receipt.bytes.length} bytes'),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('support_close_button')),
            ),
          ],
        ),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: l10n.t('admin_settlement_slip_load_failed'),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _assign() async {
    final result = await showAssignDriverDialog(
      context: context,
      api: widget.api,
      isReassign: false,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.assignDriver(widget.bookingNumber, result.driverId);
      widget.onChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver assigned successfully')),
        );
      }
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

  Future<void> _recommendDrivers() async {
    final result = await showRecommendDriversDialog(
      context: context,
      api: widget.api,
      bookingNumber: widget.bookingNumber,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.autoAssignDriver(
        widget.bookingNumber,
        driverId: result.useTopCandidate ? null : result.driverId,
        useTopCandidate: result.useTopCandidate,
        expectedAssignmentVersion: result.assignmentVersion,
      );
      widget.onChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver assigned successfully')),
        );
      }
    } catch (err) {
      if (mounted) {
        final message = userFacingError(
          err,
          fallback: context.l10n.t('ui_action_failed'),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        if (message.toLowerCase().contains('conflict') ||
            message.toLowerCase().contains('already')) {
          await _load();
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reassign() async {
    final result = await showAssignDriverDialog(
      context: context,
      api: widget.api,
      isReassign: true,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.reassignDriver(
        widget.bookingNumber,
        result.driverId,
        result.reason!,
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

  Future<void> _unassignDriver() async {
    final l10n = context.l10n;
    final reason = await showUnassignDriverDialog(
      context: context,
      bookingNumber: widget.bookingNumber,
    );
    if (reason == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.unassignDriver(widget.bookingNumber, reason);
      widget.onChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('admin_dispatch_unassign_success'))),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_unassignDriverErrorMessage(err, l10n))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmSettlement() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('admin_settlement_confirm_200')),
        content: Text(l10n.t('admin_settlement_confirm_question')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      await widget.settlementApi.approve(widget.bookingNumber);
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        final message =
            err is AdminSettlementApiException &&
                err.errorCode == 'RECEIPT_REQUIRED'
            ? l10n.t('admin_settlement_waiting_slip')
            : userFacingError(err, fallback: l10n.t('ui_action_failed'));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _manualApproveSettlement() async {
    if (_submitting) return;
    _manualSettlementNoteController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_manualSettlementText(context, 'title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_manualSettlementText(context, 'body')),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              _manualSettlementText(context, 'warning'),
              style: const TextStyle(
                color: AppTokens.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _manualSettlementNoteController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _manualSettlementText(context, 'note_label'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_manualSettlementText(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (_manualSettlementNoteController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _manualSettlementText(context, 'note_required'),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(_manualSettlementText(context, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await widget.settlementApi.manualApprove(
        widget.bookingNumber,
        _manualSettlementNoteController.text.trim(),
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

  Future<void> _scrollToSection(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _scrollToSettlement() => _scrollToSection(_pricingSectionKey);

  Future<void> _scrollToReview() => _scrollToSection(_reviewSectionKey);

  Future<void> _scrollToStatusArea() async {
    if (_operationsSummaryKey.currentContext != null) {
      await _scrollToSection(_operationsSummaryKey);
      return;
    }
    if (_assignmentSectionKey.currentContext != null) {
      await _scrollToSection(_assignmentSectionKey);
      return;
    }
    await _scrollToSection(_tripSectionKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = _allowedActions();
    final detail = _detail;

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      bottomNavigationBar: detail == null || _loading || _error != null
          ? null
          : _secondaryActionBar(l10n, actions, detail),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: l10n.t('admin_dispatch_retry'),
            )
          : AppUi.centeredContent(
              maxWidth: 900,
              child: SingleChildScrollView(
                padding: AppUi.pagePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryHeader(l10n, detail!, actions),
                    const SizedBox(height: AppTokens.spaceMd),
                    KeyedSubtree(
                      key: _operationsSummaryKey,
                      child: _operationsSummarySection(l10n, detail),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _notesSection(l10n),
                    const SizedBox(height: AppTokens.spaceMd),
                    _responsivePair(
                      _customerSection(l10n, detail),
                      KeyedSubtree(
                        key: _tripSectionKey,
                        child: _tripSection(l10n, detail),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _responsivePair(
                      KeyedSubtree(
                        key: _assignmentSectionKey,
                        child: _assignmentSection(l10n, detail),
                      ),
                      KeyedSubtree(
                        key: _pricingSectionKey,
                        child: _pricingSection(l10n, detail),
                      ),
                    ),
                    if (_hasNoShowPenalty(detail)) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _noShowPenaltySection(l10n, detail),
                    ],
                    if (detail['customerReview'] is Map) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      KeyedSubtree(
                        key: _reviewSectionKey,
                        child: _customerReviewSection(l10n, detail),
                      ),
                    ],
                    if (_statusHistory(detail).isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      KeyedSubtree(
                        key: _activitySectionKey,
                        child: _activitySection(l10n, detail),
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    _technicalSection(l10n, detail),
                    const SizedBox(height: AppTokens.spaceXl),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _notesSection(AppLocalizations l10n) {
    final remaining = 1000 - _noteController.text.length;
    final canSubmit =
        _noteController.text.trim().isNotEmpty &&
        _noteController.text.length <= 1000 &&
        !_addingNote;
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_notes_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('admin_notes_admin_only'),
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (_notes.isEmpty)
            Text(l10n.t('admin_notes_empty'))
          else
            ..._notes.map((note) {
              final author = note['author'] as Map?;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceSm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${note['text'] ?? ''}'),
                        const SizedBox(height: 4),
                        Text(
                          '${author?['name'] ?? '-'} · ${note['createdAt'] ?? '-'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          if (_notesError != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(_notesError!, style: const TextStyle(color: AppTokens.error)),
          ],
          const SizedBox(height: AppTokens.spaceSm),
          TextField(
            key: const Key('admin-note-input'),
            controller: _noteController,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.t('admin_notes_hint'),
              counterText: l10n
                  .t('admin_notes_remaining')
                  .replaceFirst('{count}', '$remaining'),
            ),
          ),
          Text(
            l10n.t('admin_notes_append_only'),
            style: const TextStyle(fontSize: 12, color: AppTokens.textMuted),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.primaryButton(
            label: l10n.t('admin_notes_add'),
            icon: Icons.note_add_outlined,
            loading: _addingNote,
            onPressed: canSubmit ? _addNote : null,
          ),
        ],
      ),
    );
  }

  Widget? _secondaryActionBar(
    AppLocalizations l10n,
    List<String> actions,
    Map<String, dynamic> detail,
  ) {
    final buttons = <Widget>[];
    if (actions.contains('RECOMMEND_DRIVERS')) {
      buttons.add(
        AppUi.secondaryButton(
          label: l10n.t('admin_detail_recommend_drivers'),
          icon: Icons.recommend_outlined,
          onPressed: _submitting ? null : _recommendDrivers,
          fullWidth: true,
        ),
      );
    }
    if (actions.contains('REASSIGN_DRIVER')) {
      buttons.add(
        AppUi.secondaryButton(
          label: l10n.t('admin_dispatch_reassign_driver'),
          icon: Icons.swap_horiz,
          onPressed: _submitting ? null : _reassign,
          fullWidth: true,
        ),
      );
    }
    if (_canUnassignDriver(detail)) {
      buttons.add(
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTokens.error,
              side: const BorderSide(color: AppTokens.error),
            ),
            onPressed: _submitting ? null : _unassignDriver,
            icon: const Icon(Icons.link_off_outlined),
            label: Text(l10n.t('admin_dispatch_unassign_driver')),
          ),
        ),
      );
    }
    if (_hasNoShowPenalty(detail)) {
      buttons.add(
        _noticeBox(
          icon: Icons.event_busy_outlined,
          text: _noShowText(context, 'already_processed'),
          isWarning: true,
        ),
      );
    } else if (_shouldShowNoShowButton(detail)) {
      buttons.add(_noShowActionButton(detail));
    }
    return buttons.isEmpty ? null : AppUi.adminStickyActions(actions: buttons);
  }

  Widget _noShowPenaltySection(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final penalty = _noShowPenalty(detail);
    if (penalty == null) return const SizedBox.shrink();

    final amount = penalty['amount'];
    final currency = penalty['currency'] as String? ?? 'THB';
    final reason = penalty['reason'] as String? ?? '-';
    final createdByAdminId = penalty['createdByAdminId'];
    final createdAt = penalty['createdAt'] as String?;

    return AppUi.adminDetailSection(
      context: context,
      title: _noShowText(context, 'section_title'),
      subtitle: _noShowText(context, 'section_subtitle'),
      backgroundColor: AppTokens.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.summaryRow(
            label: _noShowText(context, 'amount_label'),
            value: '$amount $currency',
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: _noShowText(context, 'reason_label'),
            value: reason,
          ),
          if (createdByAdminId != null)
            AppUi.summaryRow(
              label: _noShowText(context, 'processed_by'),
              value: '#$createdByAdminId',
            ),
          if (createdAt != null)
            AppUi.summaryRow(
              label: _noShowText(context, 'processed_at'),
              value:
                  _formatOptionalDate(l10n, createdAt) ??
                  _formatBangkokServiceDateTime(createdAt),
            ),
        ],
      ),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  List<Map<String, dynamic>> _sortedStatusHistory(Map<String, dynamic> detail) {
    final copy = _statusHistory(detail);
    copy.sort((a, b) {
      final bTime = _parseDateTime(b['createdAt']);
      final aTime = _parseDateTime(a['createdAt']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return copy;
  }

  Map<String, dynamic>? _latestStatusEvent(Map<String, dynamic> detail) {
    final history = _sortedStatusHistory(
      detail,
    ).where((entry) => _parseDateTime(entry['createdAt']) != null).toList();
    return history.isEmpty ? null : history.first;
  }

  DateTime? _latestStatusChangedAt(Map<String, dynamic> detail) {
    final latest = _latestStatusEvent(detail);
    return _parseDateTime(latest?['createdAt']) ??
        _parseDateTime(detail['updatedAt']);
  }

  Map<String, dynamic>? _previousReleasedDriver(Map<String, dynamic> detail) {
    final previous = detail['previousDriver'];
    if (previous is Map) {
      final map = Map<String, dynamic>.from(previous);
      final name = map['driverDisplayName']?.toString().trim();
      if (name != null && name.isNotEmpty) return map;
    }

    final history = detail['assignmentHistory'];
    if (history is! List) return null;

    Map<String, dynamic>? latest;
    DateTime? latestUnassignedAt;
    for (final item in history) {
      if (item is! Map) continue;
      final entry = Map<String, dynamic>.from(item);
      if (entry['isActive'] == true) continue;
      if (entry['assignmentReason'] != 'DRIVER_RELEASED_ASSIGNMENT') continue;
      final name = entry['driverDisplayName']?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final unassignedAt = _parseDateTime(entry['unassignedAt']);
      if (latest == null ||
          (unassignedAt != null &&
              (latestUnassignedAt == null ||
                  unassignedAt.isAfter(latestUnassignedAt)))) {
        latest = entry;
        latestUnassignedAt = unassignedAt;
      }
    }
    return latest;
  }

  String _previousReleasedDriverName(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    return _previousReleasedDriver(
          detail,
        )?['driverDisplayName']?.toString().trim() ??
        '';
  }

  String _formatBangkokServiceDateTime(String? raw) {
    final parsed = parseBackendServiceDateTime(raw);
    if (parsed == null) return '-';
    final bangkok = parsed.toUtc().add(const Duration(hours: 7));
    return _formatAbsolute(DateTime(
      bangkok.year,
      bangkok.month,
      bangkok.day,
      bangkok.hour,
      bangkok.minute,
    ));
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatAbsolute(DateTime value) {
    return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} '
        '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  String _formatAbsoluteWithRelative(AppLocalizations l10n, DateTime value) {
    final relative = _formatDuration(l10n, DateTime.now().difference(value));
    return '${_formatAbsolute(value)} · $relative ${_agoSuffix(l10n)}';
  }

  String? _formatOptionalDate(AppLocalizations l10n, dynamic value) {
    final parsed = _parseDateTime(value);
    return parsed == null ? null : _formatAbsoluteWithRelative(l10n, parsed);
  }

  String _agoSuffix(AppLocalizations l10n) {
    switch (l10n.languageCode) {
      case 'ko':
        return '전';
      case 'th':
        return 'ที่ผ่านมา';
      default:
        return 'ago';
    }
  }

  String _formatDuration(AppLocalizations l10n, Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final days = safe.inDays;
    final hours = safe.inHours % 24;
    final minutes = safe.inMinutes % 60;
    String unit(String en, String ko, String th) {
      switch (l10n.languageCode) {
        case 'ko':
          return ko;
        case 'th':
          return th;
        default:
          return en;
      }
    }

    if (days > 0) {
      final dayLabel = unit(days == 1 ? 'day' : 'days', '일', 'วัน');
      final hourLabel = unit('hr', '시간', 'ชั่วโมง');
      return hours > 0
          ? '$days $dayLabel $hours $hourLabel'
          : '$days $dayLabel';
    }
    if (safe.inHours > 0) {
      final hourLabel = unit('hr', '시간', 'ชั่วโมง');
      final minuteLabel = unit('min', '분', 'นาที');
      return minutes > 0
          ? '${safe.inHours} $hourLabel $minutes $minuteLabel'
          : '${safe.inHours} $hourLabel';
    }
    final minuteLabel = unit('min', '분', 'นาที');
    return '${safe.inMinutes} $minuteLabel';
  }

  String _settlementStatusLabel(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final status =
        (_settlement?['commissionStatus'] as String?) ??
        detail['commissionStatus'] as String?;
    switch (status) {
      case 'DUE':
      case 'OVERDUE':
      case 'PENDING':
        return l10n.t('admin_detail_settlement_required');
      case 'PAID':
      case 'APPROVED':
        return l10n.t('admin_detail_settlement_completed');
      case 'RECEIPT_SUBMITTED':
        return l10n.t('admin_detail_receipt_submitted');
      case 'REJECTED':
        return l10n.t('admin_detail_receipt_rejected');
      case 'NOT_DUE_YET':
      case 'WAIVED':
      case null:
        return '-';
      default:
        return status;
    }
  }

  String _receiptStatusLabel(AppLocalizations l10n) {
    final status = _settlement?['receiptStatus'] as String?;
    if (_hasTransferSlip) return l10n.t('admin_detail_receipt_submitted');
    switch (status) {
      case 'REJECTED':
        return l10n.t('admin_detail_receipt_rejected');
      case 'APPROVED':
        return l10n.t('admin_detail_settlement_completed');
      case 'NONE':
      case null:
        return l10n.t('admin_detail_receipt_missing');
      default:
        return status;
    }
  }

  String _actorRoleLabel(AppLocalizations l10n, String? role) {
    switch (role) {
      case 'SYSTEM':
        return l10n.t('admin_detail_actor_system');
      case 'ADMIN':
      case 'SUPER_ADMIN':
        return l10n.t('admin_detail_actor_admin');
      case 'DRIVER':
        return l10n.t('admin_detail_actor_driver');
      case 'CUSTOMER':
        return l10n.t('admin_detail_actor_customer');
      default:
        return l10n.t('admin_detail_actor_unknown');
    }
  }

  String _formatFileSize(dynamic value) {
    final bytes = value is num ? value.toDouble() : double.tryParse('$value');
    if (bytes == null || bytes <= 0) return '-';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${bytes.toStringAsFixed(0)} bytes';
  }

  Widget _summaryHeader(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
    List<String> actions,
  ) {
    final status = detail['status'] as String? ?? '';
    final operations = detail['operations'] is Map
        ? Map<String, dynamic>.from(detail['operations'] as Map)
        : null;
    final customerReview = detail['customerReview'] is Map
        ? Map<String, dynamic>.from(detail['customerReview'] as Map)
        : null;
    final lowRating =
        customerReview?['lowRating'] == true ||
        operations?['lowRating'] == true;
    final severity = operations?['severity'] as String?;
    final reason = AdminOperationsUx.formatActionReason(l10n, operations);
    final secondaryReasons = AdminOperationsUx.secondaryActionReasonLabels(
      l10n,
      operations,
    );
    final route = Map<String, dynamic>.from(detail['route'] as Map? ?? {});
    final origin = Map<String, dynamic>.from(route['origin'] as Map? ?? {});
    final destination = Map<String, dynamic>.from(
      route['destination'] as Map? ?? {},
    );

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bookingNumber,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTokens.primaryDark,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppUi.statusBadge(
                BookingStatusDisplay.label(
                  l10n,
                  status,
                  audience: BookingStatusAudience.admin,
                ),
                tone: AppUi.toneForBookingStatus(status),
              ),
              if (severity != null && severity.isNotEmpty)
                AppUi.statusBadge(
                  AdminOperationsUx.severityLabel(l10n, severity),
                  tone: severity == 'CRITICAL' || severity == 'URGENT'
                      ? AppStatusTone.error
                      : AppStatusTone.warning,
                ),
              if (lowRating)
                AppUi.statusBadge(
                  l10n.t('admin_booking_low_rating_badge'),
                  tone: AppStatusTone.warning,
                ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              reason,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTokens.warning,
              ),
            ),
          ],
          if (secondaryReasons.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: Text(
                l10n
                    .t('admin_ops_more_reasons')
                    .replaceAll('{count}', '${secondaryReasons.length}'),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final secondaryReason in secondaryReasons)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $secondaryReason',
                        style: const TextStyle(color: AppTokens.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n.t('admin_ops_next_action_label'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            AdminOperationsUx.nextActionLabel(l10n, operations, detail),
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${l10n.t('admin_pickup_requested_at')} : ',
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
                TextSpan(
                  text: _formatBangkokServiceDateTime(
                    detail['scheduledPickupAt'] as String?,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _AdminOperationsRouteText(origin: origin, destination: destination),
          if (_primaryAction(l10n, actions) case final action?) ...[
            const SizedBox(height: AppTokens.spaceMd),
            action,
          ],
        ],
      ),
    );
  }

  Widget _operationsSummarySection(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final status = detail['status'] as String? ?? '';
    final operations = detail['operations'] is Map
        ? Map<String, dynamic>.from(detail['operations'] as Map)
        : null;
    final assignment = detail['activeAssignment'] is Map
        ? Map<String, dynamic>.from(detail['activeAssignment'] as Map)
        : null;
    final latest = _latestStatusEvent(detail);
    final changedAt = _latestStatusChangedAt(detail);
    final reason = operations?['primaryActionReason'] as String?;
    final diagnostic = AdminOperationsUx.statusDiagnosticLabel(l10n, reason);
    final driverName =
        assignment?['driverDisplayName'] as String? ??
        l10n.t('admin_dispatch_unassigned');
    final driverStatus = assignment?['driverStatus'] as String?;
    final assignmentStatus = assignment == null
        ? l10n.t('admin_dispatch_unassigned')
        : assignment['status'] as String? ?? '-';
    final previousDriverName = _previousReleasedDriverName(l10n, detail);
    final summaryRows = <Widget>[
      AppUi.summaryRow(
        label: l10n.t('admin_detail_current_status'),
        value: BookingStatusDisplay.label(
          l10n,
          status,
          audience: BookingStatusAudience.admin,
        ),
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_last_status_change'),
        value: changedAt == null
            ? '-'
            : _formatAbsoluteWithRelative(l10n, changedAt),
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_status_duration'),
        value: changedAt == null
            ? '-'
            : _formatDuration(l10n, DateTime.now().difference(changedAt)),
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_driver_assignment_status'),
        value: '$driverName · $assignmentStatus',
      ),
      if (previousDriverName.isNotEmpty)
        AppUi.summaryRow(
          label: l10n.t('admin_detail_previous_driver'),
          value: previousDriverName,
        ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_driver_status'),
        value: driverStatus ?? '-',
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_settlement_status'),
        value: _settlementStatusLabel(l10n, detail),
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_receipt_status'),
        value: _receiptStatusLabel(l10n),
      ),
      AppUi.summaryRow(
        label: l10n.t('admin_detail_recommended_action'),
        value: AdminOperationsUx.nextActionLabel(l10n, operations, detail),
      ),
    ];

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_operations_summary'),
      backgroundColor:
          diagnostic.isNotEmpty || _hasSettlementStateMismatch(detail)
          ? AppTokens.warningLight
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryGrid(summaryRows),
          if (latest != null &&
              (latest['memo'] as String?)?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _noticeBox(
              icon: Icons.sticky_note_2_outlined,
              text:
                  '${l10n.t('admin_detail_additional_memo')}: ${latest['memo']}',
            ),
          ],
          if (diagnostic.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _noticeBox(icon: Icons.manage_search_outlined, text: diagnostic),
          ],
          if (_hasSettlementStateMismatch(detail)) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _noticeBox(
              icon: Icons.warning_amber_outlined,
              text: l10n.t('admin_detail_settlement_state_mismatch'),
              isWarning: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryGrid(List<Widget> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(children: rows);
        }
        return Wrap(
          spacing: AppTokens.spaceMd,
          runSpacing: 0,
          children: rows
              .map(
                (row) => SizedBox(
                  width: (constraints.maxWidth - AppTokens.spaceMd) / 2,
                  child: row,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required String text,
    bool isWarning = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: isWarning ? AppTokens.warningLight : AppTokens.surfaceMuted,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(
          color: isWarning ? AppTokens.warning : AppTokens.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: isWarning ? AppTokens.warning : AppTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget? _primaryAction(AppLocalizations l10n, List<String> actions) {
    final operations = _detail?['operations'] as Map?;
    final primaryCta =
        _detail?['primaryCta'] as String? ??
        operations?['primaryCta'] as String?;
    if (primaryCta == 'ASSIGN_DRIVER' && actions.contains('ASSIGN_DRIVER')) {
      return AppUi.primaryButton(
        label: l10n.t('admin_dispatch_assign_driver'),
        icon: Icons.person_add_alt,
        loading: _submitting,
        onPressed: _submitting ? null : _assign,
      );
    }
    if (primaryCta == 'CONFIRM_SETTLEMENT' && _canConfirmSettlement) {
      return AppUi.primaryButton(
        label: l10n.t('admin_settlement_confirm_200'),
        icon: Icons.payments_outlined,
        loading: _submitting,
        onPressed: _submitting ? null : _confirmSettlement,
      );
    }
    if (primaryCta == 'SETTLEMENT_DETAIL') {
      return AppUi.primaryButton(
        label: l10n.t('admin_ops_cta_settlement_detail'),
        icon: Icons.receipt_long_outlined,
        onPressed: _scrollToSettlement,
      );
    }
    if (primaryCta == 'REVIEW_RATING') {
      return AppUi.primaryButton(
        label: l10n.t('admin_ops_cta_review_rating'),
        icon: Icons.rate_review_outlined,
        onPressed: _scrollToReview,
      );
    }
    if (primaryCta == 'CHECK_STATUS') {
      return AppUi.primaryButton(
        label: l10n.t('admin_ops_cta_check_status'),
        icon: Icons.manage_search_outlined,
        onPressed: _scrollToStatusArea,
      );
    }
    if (_canConfirmSettlement) {
      return AppUi.primaryButton(
        label: l10n.t('admin_settlement_confirm_200'),
        icon: Icons.payments_outlined,
        loading: _submitting,
        onPressed: _submitting ? null : _confirmSettlement,
      );
    }
    if (_canManualApproveSettlement) {
      return AppUi.primaryButton(
        label: _manualSettlementText(context, 'button'),
        icon: Icons.verified_user_outlined,
        loading: _submitting,
        onPressed: _submitting ? null : _manualApproveSettlement,
      );
    }
    if (actions.contains('ASSIGN_DRIVER')) {
      return AppUi.primaryButton(
        label: l10n.t('admin_dispatch_assign_driver'),
        icon: Icons.person_add_alt,
        loading: _submitting,
        onPressed: _submitting ? null : _assign,
      );
    }
    return null;
  }

  Widget _responsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              first,
              const SizedBox(height: AppTokens.spaceMd),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppTokens.spaceMd),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _tripSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final route = Map<String, dynamic>.from(detail['route'] as Map);
    final origin = Map<String, dynamic>.from(route['origin'] as Map);
    final destination = Map<String, dynamic>.from(route['destination'] as Map);
    final vehicle = Map<String, dynamic>.from(detail['vehicle'] as Map? ?? {});
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_trip'),
      child: Column(
        children: [
          AppUi.summaryRow(
            label: l10n.t('service_type'),
            value: (detail['serviceType'] as Map?)?['name'] as String? ?? '-',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_pickup_requested_at'),
            value: _formatBangkokServiceDateTime(
              detail['scheduledPickupAt'] as String?,
            ),
          ),
          _LocationSummaryRow(
            label: l10n.t('origin'),
            location: origin,
          ),
          _LocationSummaryRow(
            label: l10n.t('destination'),
            location: destination,
          ),
          AppUi.summaryRow(
            label: 'Vehicle',
            value: vehicle['typeName'] as String? ?? '-',
          ),
          if (_hasFlight(detail)) ..._flightRows(l10n, detail),
          if (detail['createdAt'] != null)
            AppUi.summaryRow(
              label: l10n.t('admin_detail_created'),
              value: _formatBangkokServiceDateTime(
                detail['createdAt'] as String?,
              ),
            ),
        ],
      ),
    );
  }

  Widget _customerSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final customer = Map<String, dynamic>.from(detail['customer'] as Map);
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_customer'),
      child: Column(
        children: [
          AppUi.summaryRow(
            label: l10n.t('name'),
            value: customer['name'] as String? ?? '',
          ),
          AppUi.summaryRow(
            label: l10n.t('phone'),
            value: customer['phone'] as String? ?? '',
          ),
          if (customer['messengerType'] != null)
            AppUi.summaryRow(
              label: l10n.t('messenger_type'),
              value: customer['messengerType'] as String,
            ),
          if (customer['messengerId'] != null)
            AppUi.summaryRow(
              label: l10n.t('messenger_id'),
              value: customer['messengerId'] as String,
            ),
          if (customer['email'] != null)
            AppUi.summaryRow(
              label: l10n.t('email'),
              value: customer['email'] as String,
            ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_country'),
            value: (customer['countryCode'] as String? ?? '').trim().isEmpty
                ? '-'
                : CountryCatalog.displayName(
                    customer['countryCode'] as String,
                    l10n,
                  ),
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_passengers'),
            value:
                '${(detail['passengers'] as Map?)?['adults'] ?? 0} / ${(detail['passengers'] as Map?)?['children'] ?? 0} / ${(detail['passengers'] as Map?)?['infants'] ?? 0}',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_luggage'),
            value:
                '20" ${(detail['luggage'] as Map?)?['carriers20Inch'] ?? 0} · 24"+ ${(detail['luggage'] as Map?)?['carriers24InchPlus'] ?? 0} · Golf ${(detail['luggage'] as Map?)?['golfBags'] ?? 0}',
          ),
          if ('${detail['specialRequests'] ?? ''}'.isNotEmpty)
            AppUi.summaryRow(
              label: l10n.t('admin_detail_special_requests'),
              value: '${detail['specialRequests']}',
            ),
        ],
      ),
    );
  }

  Widget _assignmentSection(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final assignment = detail['activeAssignment'] is Map
        ? Map<String, dynamic>.from(detail['activeAssignment'] as Map)
        : null;
    final vehicle = assignment?['vehicle'] is Map
        ? Map<String, dynamic>.from(assignment!['vehicle'] as Map)
        : null;

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_driver_vehicle'),
      backgroundColor: assignment == null ? AppTokens.warningLight : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('admin_dispatch_assigned_driver'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (assignment == null)
            AppUi.summaryRow(
              label: l10n.t('admin_dispatch_assignment'),
              value: l10n.t('admin_dispatch_unassigned'),
            )
          else ...[
            AppUi.summaryRow(
              label: l10n.t('name'),
              value: assignment['driverDisplayName'] as String? ?? '',
            ),
            if (assignment['driverStatus'] != null)
              AppUi.summaryRow(
                label: l10n.t('status'),
                value: assignment['driverStatus'] as String,
              ),
            if (vehicle != null) ...[
              AppUi.summaryRow(
                label: l10n.t('airport_meeting_vehicle_type'),
                value: _vehicleTypeLabel(vehicle),
              ),
              AppUi.summaryRow(
                label: l10n.t('airport_meeting_vehicle_plate'),
                value: _vehiclePlateLabel(vehicle),
              ),
            ],
            if (assignment['assignedAt'] != null)
              AppUi.summaryRow(
                label: 'Assigned at',
                value: assignment['assignedAt'] as String,
              ),
            AppUi.summaryRow(
              label: l10n.t('admin_dispatch_assignment'),
              value: assignment['status'] as String? ?? '',
            ),
          ],
        ],
      ),
    );
  }

  Widget _customerReviewSection(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final review = Map<String, dynamic>.from(detail['customerReview'] as Map);
    final rating = review['rating'] as num?;
    final tags = (review['tags'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    final comment = (review['comment'] as String?)?.trim();
    final createdAt = (review['createdAt'] as String?)?.trim();
    final lowRating = review['lowRating'] == true;

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_booking_review_section'),
      backgroundColor: lowRating ? AppTokens.warningLight : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rating != null) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  '${l10n.t('admin_booking_review_rating')}:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    return Icon(
                      value <= rating.toInt()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: lowRating
                          ? AppTokens.warning
                          : Colors.amber.shade700,
                      size: 20,
                    );
                  }),
                ),
                Text('${rating.toInt()}/5'),
              ],
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.t('admin_booking_review_tags'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map(
                    (code) => Chip(
                      label: Text(l10n.t(ReviewTags.labelKey(code))),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _customerReviewCommentCard(l10n, comment),
          ] else ...[
            const SizedBox(height: AppTokens.spaceSm),
            _customerReviewEmptyComment(l10n),
          ],
          if (createdAt != null && createdAt.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.t('admin_booking_review_created_at'),
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              createdAt,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customerReviewCommentCard(AppLocalizations l10n, String comment) {
    final displayComment = _wrapLongReviewRuns(comment);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              const Icon(
                Icons.rate_review_outlined,
                size: 18,
                color: AppTokens.primary,
              ),
              Text(
                l10n.t('admin_booking_review_comment'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            displayComment,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _wrapLongReviewRuns(String text) {
    const wrapEvery = 32;
    final buffer = StringBuffer();
    var runLength = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      if (char.trim().isEmpty) {
        runLength = 0;
        continue;
      }
      runLength += 1;
      if (runLength >= wrapEvery) {
        buffer.write('\u200B');
        runLength = 0;
      }
    }
    return buffer.toString();
  }

  Widget _customerReviewEmptyComment(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: Text(
        l10n.t('admin_booking_review_comment_empty'),
        style: const TextStyle(
          color: AppTokens.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  bool _hasFlight(Map<String, dynamic> detail) {
    final flight = detail['flight'];
    if (flight is! Map) return false;
    return (flight['flightNumber'] as String?)?.isNotEmpty == true;
  }

  List<Widget> _flightRows(AppLocalizations l10n, Map<String, dynamic> detail) {
    final flight = Map<String, dynamic>.from(detail['flight'] as Map);
    return [
      AppUi.summaryRow(
        label: l10n.t('admin_detail_flight'),
        value: flight['flightNumber'] as String? ?? '-',
      ),
      if (flight['airportIata'] != null)
        AppUi.summaryRow(
          label: 'Airport',
          value: flight['airportIata'] as String,
        ),
      if (flight['scheduledArrivalAt'] != null)
        AppUi.summaryRow(
          label: 'Scheduled arrival',
          value: flight['scheduledArrivalAt'] as String,
        ),
      if (flight['estimatedArrivalAt'] != null)
        AppUi.summaryRow(
          label: 'Estimated arrival',
          value: flight['estimatedArrivalAt'] as String,
        ),
      if (flight['delayStatus'] != null)
        AppUi.summaryRow(
          label: 'Delay status',
          value: flight['delayStatus'] as String,
        ),
      if (flight['delayMinutes'] != null)
        AppUi.summaryRow(
          label: 'Delay minutes',
          value: '${flight['delayMinutes']}',
        ),
    ];
  }

  Widget _pricingSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final pricing = Map<String, dynamic>.from(detail['pricing'] as Map);
    final chargeItems = pricing['chargeItems'] as List<dynamic>? ?? [];

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_pricing_settlement'),
      backgroundColor: AppTokens.accentLight,
      child: Column(
        children: [
          for (final raw in chargeItems)
            AppUi.summaryRow(
              label: _chargeLabel(raw),
              value: '${_chargeAmount(raw)} ${pricing['currency']}',
            ),
          if (chargeItems.isNotEmpty) const Divider(height: 20),
          AppUi.summaryRow(
            label: l10n.t('total'),
            value: '${pricing['totalAmount']} ${pricing['currency']}',
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: l10n.t('payment_method'),
            value: pricing['paymentMethod'] as String? ?? '',
          ),
          if (pricing['paymentStatus'] != null)
            AppUi.summaryRow(
              label: 'Payment status',
              value: pricing['paymentStatus'] as String,
            ),
          if (_settlementVisible(detail)) ...[
            const Divider(height: 24),
            Text(
              l10n.t('admin_settlement_section'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            _settlementSectionContent(l10n, detail),
          ],
        ],
      ),
    );
  }

  Widget _settlementSectionContent(
    AppLocalizations l10n,
    Map<String, dynamic> detail,
  ) {
    final settlement = _settlement;
    final metadata = settlement?['receiptMetadata'] is Map
        ? Map<String, dynamic>.from(settlement!['receiptMetadata'] as Map)
        : null;
    final approval = settlement?['approval'] is Map
        ? Map<String, dynamic>.from(settlement!['approval'] as Map)
        : null;
    final reviewHistory = settlement?['reviewHistory'] as List<dynamic>? ?? [];
    final latestReview = reviewHistory.whereType<Map>().isEmpty
        ? null
        : Map<String, dynamic>.from(reviewHistory.whereType<Map>().last);
    final rejectionReason = settlement?['rejectionReason'] as String?;
    final isRejected =
        settlement?['receiptStatus'] == 'REJECTED' ||
        settlement?['commissionStatus'] == 'REJECTED';
    final amount = settlement?['commissionAmount'];
    final currency = settlement?['currency'] as String? ?? 'THB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppUi.statusBadge(
              _settlementStatusLabel(l10n, detail),
              tone: isRejected
                  ? AppStatusTone.error
                  : _hasTransferSlip
                  ? AppStatusTone.warning
                  : AppStatusTone.info,
            ),
            AppUi.statusBadge(
              _receiptStatusLabel(l10n),
              tone: isRejected ? AppStatusTone.error : AppStatusTone.info,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        AppUi.summaryRow(
          label: l10n.t('admin_settlement_status'),
          value: _settlementStatusLabel(l10n, detail),
        ),
        if (amount != null)
          AppUi.summaryRow(label: l10n.t('amount'), value: '$amount $currency'),
        AppUi.summaryRow(
          label: l10n.t('admin_detail_settlement_actionable'),
          value: _canConfirmSettlement || _canManualApproveSettlement
              ? l10n.t('yes')
              : l10n.t('admin_detail_settlement_not_actionable'),
        ),
        AppUi.summaryRow(
          label: l10n.t('admin_settlement_transfer_slip'),
          value: _receiptStatusLabel(l10n),
        ),
        if (settlement?['receiptSubmittedAt'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_receipt_submitted_at'),
            value:
                _formatOptionalDate(l10n, settlement?['receiptSubmittedAt']) ??
                '${settlement?['receiptSubmittedAt']}',
          ),
        if (settlement?['receiptUploadedAt'] != null &&
            settlement?['receiptUploadedAt'] !=
                settlement?['receiptSubmittedAt'])
          AppUi.summaryRow(
            label: l10n.t('admin_detail_receipt_uploaded_at'),
            value:
                _formatOptionalDate(l10n, settlement?['receiptUploadedAt']) ??
                '${settlement?['receiptUploadedAt']}',
          ),
        if (metadata?['originalFilename'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_receipt_file'),
            value: metadata!['originalFilename'] as String,
          ),
        if (metadata?['mimeType'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_receipt_content_type'),
            value: metadata!['mimeType'] as String,
          ),
        if (metadata?['fileSize'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_receipt_file_size'),
            value: _formatFileSize(metadata!['fileSize']),
          ),
        if (isRejected) ...[
          const SizedBox(height: AppTokens.spaceSm),
          _noticeBox(
            icon: Icons.report_problem_outlined,
            isWarning: true,
            text:
                '${l10n.t('admin_detail_rejection_reason')}: '
                '${(rejectionReason?.trim().isNotEmpty == true) ? rejectionReason : l10n.t('admin_detail_rejection_reason_missing')}',
          ),
          if (latestReview?['reviewedAt'] != null)
            AppUi.summaryRow(
              label: l10n.t('admin_detail_rejected_at'),
              value:
                  _formatOptionalDate(l10n, latestReview?['reviewedAt']) ??
                  '${latestReview?['reviewedAt']}',
            ),
        ],
        if (approval?['approvedAt'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_settlement_approved_at'),
            value:
                _formatOptionalDate(l10n, approval?['approvedAt']) ??
                '${approval?['approvedAt']}',
          ),
        if (approval?['mode'] != null)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_settlement_approval_mode'),
            value: '${approval?['mode']}',
          ),
        if (approval?['receiptMissingAtApproval'] == true)
          AppUi.summaryRow(
            label: l10n.t('admin_detail_settlement_manual_approval'),
            value: l10n.t('yes'),
          ),
        if (_hasSettlementStateMismatch(detail)) ...[
          const SizedBox(height: AppTokens.spaceSm),
          _noticeBox(
            icon: Icons.warning_amber_outlined,
            text: l10n.t('admin_detail_settlement_state_mismatch'),
            isWarning: true,
          ),
        ],
        if (_settlementError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _settlementError!,
                style: const TextStyle(color: AppTokens.error),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              AppUi.secondaryButton(
                label: l10n.t('admin_detail_retry_settlement'),
                icon: Icons.refresh,
                onPressed: _submitting ? null : _retrySettlement,
                fullWidth: true,
              ),
            ],
          )
        else if (!_hasTransferSlip)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.t('admin_settlement_waiting_slip')),
              if (!_canManualApproveSettlement)
                Text(l10n.t('admin_detail_settlement_not_actionable')),
              if (_canManualApproveSettlement) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  _manualSettlementText(context, 'section_hint'),
                  style: const TextStyle(
                    color: AppTokens.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                AppUi.primaryButton(
                  label: _manualSettlementText(context, 'button'),
                  icon: Icons.verified_user_outlined,
                  loading: _submitting,
                  onPressed: _submitting ? null : _manualApproveSettlement,
                ),
              ],
            ],
          )
        else
          AppUi.secondaryButton(
            label: l10n.t('admin_settlement_view_slip'),
            icon: Icons.receipt_long_outlined,
            onPressed: _submitting ? null : _viewTransferSlip,
            fullWidth: true,
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _statusHistory(Map<String, dynamic> detail) {
    return (detail['statusHistory'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Widget _activitySection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final history = _sortedStatusHistory(detail);
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_status_history'),
      child: Column(
        children: history.map((entry) {
          final from = entry['fromStatus'] as String? ?? '-';
          final to = entry['toStatus'] as String? ?? '-';
          final when =
              _formatOptionalDate(l10n, entry['createdAt']) ??
              entry['createdAt'] as String? ??
              '';
          final role = entry['changedByRole'] as String? ?? '';
          final memo = (entry['memo'] as String?)?.trim();
          final fromLabel = from == '-'
              ? from
              : BookingStatusDisplay.label(
                  l10n,
                  from,
                  audience: BookingStatusAudience.admin,
                );
          final toLabel = to == '-'
              ? to
              : BookingStatusDisplay.label(
                  l10n,
                  to,
                  audience: BookingStatusAudience.admin,
                );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history, size: 18, color: AppTokens.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$fromLabel → $toLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (when.isNotEmpty)
                        Text(
                          when,
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      if (role.isNotEmpty)
                        Text(
                          _actorRoleLabel(l10n, role),
                          style: const TextStyle(
                            color: AppTokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      if (entry['reason'] != null)
                        Text(
                          '${entry['reason']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      if (memo != null && memo.isNotEmpty)
                        Text(
                          '${l10n.t('admin_detail_additional_memo')}: $memo',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
                AppUi.statusBadge(
                  toLabel,
                  tone: AppUi.toneForBookingStatus(to),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _technicalSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final serviceType = detail['serviceType'] as Map?;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const Key('admin-detail-technical'),
        title: Text(l10n.t('admin_detail_technical')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          AppUi.summaryRow(
            label: l10n.t('admin_detail_booking_id'),
            value: '${detail['id'] ?? '-'}',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_raw_status'),
            value: '${detail['status'] ?? '-'}',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_service_code'),
            value: '${serviceType?['code'] ?? '-'}',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_updated'),
            value: '${detail['updatedAt'] ?? '-'}',
          ),
        ],
      ),
    );
  }

  String _vehicleTypeLabel(Map<String, dynamic> vehicle) {
    final typeName = (vehicle['typeName'] as String?)?.trim();
    if (typeName != null && typeName.isNotEmpty) return typeName;
    final typeCode = (vehicle['typeCode'] as String?)?.trim();
    if (typeCode != null && typeCode.isNotEmpty) return typeCode;
    return '-';
  }

  String _vehiclePlateLabel(Map<String, dynamic> vehicle) {
    final plate = (vehicle['plateNumber'] as String?)?.trim();
    return plate == null || plate.isEmpty ? '-' : plate;
  }

  // ignore: unused_element
  String _vehicleSummary(Map<String, dynamic> vehicle) {
    return [
      vehicle['typeCode'],
      vehicle['plateNumber'],
      vehicle['modelName'],
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
  }

  String _chargeLabel(dynamic raw) {
    return Map<String, dynamic>.from(raw as Map)['description'] as String? ??
        'Charge';
  }

  num? _chargeAmount(dynamic raw) {
    return Map<String, dynamic>.from(raw as Map)['amount'] as num?;
  }
}

const _adminLocationHighlightColor = Color(0xFF006A60);

String? _adminLocationName(Map<String, dynamic> location) {
  final nameTh = (location['nameTh'] as String?)?.trim();
  if (nameTh != null && nameTh.isNotEmpty) {
    return nameTh;
  }
  final name = (location['name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  return null;
}

String? _adminLocationAddress(Map<String, dynamic> location) {
  final address = (location['address'] as String?)?.trim();
  if (address == null || address.isEmpty) {
    return null;
  }
  return address;
}

class _AdminOperationsRouteText extends StatelessWidget {
  const _AdminOperationsRouteText({
    required this.origin,
    required this.destination,
  });

  final Map<String, dynamic> origin;
  final Map<String, dynamic> destination;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminOperationsRouteEndpoint(
          label: l10n.t('origin'),
          location: origin,
        ),
        const SizedBox(height: 4),
        _AdminOperationsRouteEndpoint(
          label: l10n.t('destination'),
          location: destination,
        ),
      ],
    );
  }
}

class _AdminOperationsRouteEndpoint extends StatelessWidget {
  const _AdminOperationsRouteEndpoint({
    required this.label,
    required this.location,
  });

  final String label;
  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final name = _adminLocationName(location);
    final address = _adminLocationAddress(location);

    return Text.rich(
      TextSpan(
        style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
        children: [
          TextSpan(text: '$label : '),
          ..._endpointSpans(name, address),
        ],
      ),
    );
  }

  List<InlineSpan> _endpointSpans(String? name, String? address) {
    if (name == null) {
      return [TextSpan(text: address ?? '-')];
    }
    final showAddress =
        address != null && address.isNotEmpty && address != name;
    return [
      TextSpan(
        text: name,
        style: const TextStyle(
          color: _adminLocationHighlightColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      if (showAddress)
        TextSpan(
          children: [
            const TextSpan(text: '\n'),
            TextSpan(text: address),
          ],
        ),
    ];
  }
}

class _LocationSummaryRow extends StatelessWidget {
  const _LocationSummaryRow({
    required this.label,
    required this.location,
  });

  final String label;
  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final name = _adminLocationName(location);
    final address = _adminLocationAddress(location);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: name != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _adminLocationHighlightColor,
                          height: 1.35,
                        ),
                      ),
                      if (address != null && address != name) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppTokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  )
                : Text(
                    address ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.textPrimary,
                      height: 1.35,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _manualSettlementText(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  const values = {
    'en': {
      'button': 'Manual settlement approval',
      'title': 'Manual settlement approval',
      'body':
          'No transfer slip has been uploaded. Have you confirmed the actual deposit or separate settlement?',
      'warning':
          'This settlement will be marked complete. If the driver has no other unresolved settlements, they can receive new calls again.',
      'confirm': 'Confirm approval',
      'note_label': 'Approval reason or confirmation note',
      'note_required': 'Please enter an approval note.',
      'section_hint':
          'Use only after confirming payment outside the transfer slip flow.',
      'cancel': 'Cancel',
    },
    'ko': {
      'button': '수동 정산 승인',
      'title': '수동 정산 승인',
      'body': '송금증이 업로드되지 않았습니다. 실제 입금 또는 별도 정산이 완료된 것을 확인하셨습니까?',
      'warning': '이 정산 건이 완료 처리됩니다. 다른 미정산 건이 없으면 해당 기사님은 다시 신규 콜을 받을 수 있습니다.',
      'confirm': '확인 후 승인',
      'note_label': '승인 사유 또는 확인 내용',
      'note_required': '승인 메모를 입력해 주세요.',
      'section_hint': '송금증 없이 외부 입금 확인이 끝난 경우에만 사용하세요.',
      'cancel': '취소',
    },
    'th': {
      'button': 'อนุมัติการชำระด้วยตนเอง',
      'title': 'อนุมัติการชำระด้วยตนเอง',
      'body':
          'ยังไม่มีการอัปโหลดสลิปโอนเงิน คุณยืนยันการรับเงินหรือการชำระแยกแล้วใช่หรือไม่?',
      'warning':
          'รายการชำระนี้จะถูกทำเครื่องหมายว่าเสร็จสิ้น หากคนขับไม่มีรายการค้างชำระอื่น จะสามารถรับงานใหม่ได้อีกครั้ง',
      'confirm': 'ยืนยันการอนุมัติ',
      'note_label': 'เหตุผลหรือบันทึกการยืนยัน',
      'note_required': 'กรุณากรอกบันทึกการอนุมัติ',
      'section_hint': 'ใช้เฉพาะเมื่อยืนยันการชำระเงินนอกขั้นตอนสลิปโอนเงินแล้ว',
      'cancel': 'ยกเลิก',
    },
  };
  return values[language]?[key] ?? values['en']![key] ?? key;
}

String _noShowText(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  const values = {
    'en': {
      'button': 'Mark no-show',
      'title': 'Mark booking as no-show',
      'body':
          'Record a separate no-show penalty for this booking. This is not part of commission settlement.',
      'warning': 'This action cannot be undone.',
      'confirm': 'Confirm no-show',
      'penalty_label': 'Penalty amount (THB)',
      'amount_label': 'Amount',
      'reason_label': 'Reason',
      'memo_label': 'Memo (optional)',
      'cancel': 'Cancel',
      'success': 'No-show recorded successfully.',
      'already_processed': 'No-show already recorded for this booking.',
      'section_title': 'No-show penalty',
      'section_subtitle':
          'Separate admin record — not linked to commission settlement.',
      'processed_by': 'Processed by admin',
      'processed_at': 'Processed at',
      'error_already_processed': 'This booking has already been marked no-show.',
      'error_invalid_status':
          'No-show cannot be recorded for the current booking status.',
      'error_validation': 'Please check the no-show form and try again.',
      'error_action_failed': 'Unable to record no-show.',
      'error_forbidden': 'You do not have permission to record no-show.',
    },
    'ko': {
      'button': '노쇼 처리',
      'title': '노쇼 처리',
      'body':
          '이 예약에 대한 노쇼 패널티를 별도로 기록합니다. 수수료 정산과는 별개입니다.',
      'warning': '이 작업은 되돌릴 수 없습니다.',
      'confirm': '노쇼 처리 확인',
      'penalty_label': '패널티 금액 (THB)',
      'amount_label': '금액',
      'reason_label': '사유',
      'memo_label': '메모 (선택)',
      'cancel': '취소',
      'success': '노쇼 처리가 완료되었습니다.',
      'already_processed': '이미 노쇼 처리된 예약입니다.',
      'section_title': '노쇼 패널티',
      'section_subtitle': '정산과 별도로 관리되는 관리자 기록입니다.',
      'processed_by': '처리 관리자',
      'processed_at': '처리 시각',
      'error_already_processed': '이미 노쇼 처리된 예약입니다.',
      'error_invalid_status': '현재 예약 상태에서는 노쇼 처리할 수 없습니다.',
      'error_validation': '입력값을 확인한 뒤 다시 시도해 주세요.',
      'error_action_failed': '노쇼 처리에 실패했습니다.',
      'error_forbidden': '노쇼 처리 권한이 없습니다.',
    },
    'th': {
      'button': 'บันทึก no-show',
      'title': 'บันทึก no-show',
      'body':
          'บันทึกค่าปรับ no-show แยกจากรายการนี้ ไม่ใช่ส่วนหนึ่งของการชำระค่าคอมมิชชัน',
      'warning': 'ไม่สามารถยกเลิกการทำรายการนี้ได้',
      'confirm': 'ยืนยัน no-show',
      'penalty_label': 'จำนวนค่าปรับ (THB)',
      'amount_label': 'จำนวนเงิน',
      'reason_label': 'เหตุผล',
      'memo_label': 'บันทึก (ไม่บังคับ)',
      'cancel': 'ยกเลิก',
      'success': 'บันทึก no-show สำเร็จแล้ว',
      'already_processed': 'รายการนี้ถูกบันทึก no-show แล้ว',
      'section_title': 'ค่าปรับ no-show',
      'section_subtitle': 'บันทึกแยกจากการชำระค่าคอมมิชชัน',
      'processed_by': 'ผู้ดูแลที่ดำเนินการ',
      'processed_at': 'เวลาที่ดำเนินการ',
      'error_already_processed': 'รายการนี้ถูกบันทึก no-show แล้ว',
      'error_invalid_status': 'ไม่สามารถบันทึก no-show ในสถานะปัจจุบันได้',
      'error_validation': 'กรุณาตรวจสอบข้อมูลแล้วลองอีกครั้ง',
      'error_action_failed': 'ไม่สามารถบันทึก no-show ได้',
      'error_forbidden': 'คุณไม่มีสิทธิ์บันทึก no-show',
    },
  };
  return values[language]?[key] ?? values['en']![key] ?? key;
}
