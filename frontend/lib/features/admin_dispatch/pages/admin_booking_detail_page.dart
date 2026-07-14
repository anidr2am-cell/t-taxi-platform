import 'package:flutter/material.dart';

import '../../booking/utils/booking_status_display.dart';
import '../../booking/utils/review_tags.dart';
import '../../booking/models/country_option.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_chat/pages/admin_chat_queue_page.dart';
import '../services/admin_dispatch_api_service.dart';
import '../../admin_settlement/services/admin_settlement_api_service.dart';
import '../../settlement/utils/settlement_receipt.dart';
import '../widgets/assign_driver_dialog.dart';
import '../widgets/recommend_drivers_dialog.dart';
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
  List<Map<String, dynamic>> _notes = [];
  String? _notesError;
  bool _addingNote = false;

  @override
  void dispose() {
    _noteController.dispose();
    _manualSettlementNoteController.dispose();
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
      if (detail['status'] == 'SETTLEMENT_PENDING') {
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

  bool get _hasTransferSlip => settlementReceiptPresent(_settlement);

  bool get _canConfirmSettlement =>
      _detail?['status'] == 'SETTLEMENT_PENDING' &&
      settlementCanApprove(_settlement);

  bool get _canManualApproveSettlement =>
      _detail?['status'] == 'SETTLEMENT_PENDING' &&
      _settlement?['canManualApprove'] == true;

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

  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (chatContext) => AdminChatDetailPage(
          bookingNumber: widget.bookingNumber,
          onBack: () => Navigator.of(chatContext).pop(),
        ),
      ),
    );
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
          : _secondaryActionBar(l10n, actions),
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
                    _notesSection(l10n),
                    const SizedBox(height: AppTokens.spaceMd),
                    _responsivePair(
                      _customerSection(l10n, detail),
                      _tripSection(l10n, detail),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _responsivePair(
                      _assignmentSection(l10n, detail),
                      _pricingSection(l10n, detail),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _chatSection(l10n, detail),
                    if (detail['customerReview'] is Map) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _customerReviewSection(l10n, detail),
                    ],
                    if (_statusHistory(detail).isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _activitySection(l10n, detail),
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

  Widget? _secondaryActionBar(AppLocalizations l10n, List<String> actions) {
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
    return buttons.isEmpty ? null : AppUi.adminStickyActions(actions: buttons);
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
    final extraReasonCount = operations?['extraActionReasonCount'] as int? ?? 0;
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
                  tone: severity == 'URGENT'
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
          if (extraReasonCount > 0)
            Text(
              l10n
                  .t('admin_detail_more_reasons')
                  .replaceFirst('{count}', '$extraReasonCount'),
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
          Text(
            detail['scheduledPickupAt'] as String? ?? '-',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${origin['address'] ?? '-'} → ${destination['address'] ?? '-'}',
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          if (_primaryAction(l10n, actions) case final action?) ...[
            const SizedBox(height: AppTokens.spaceMd),
            action,
          ],
        ],
      ),
    );
  }

  Widget? _primaryAction(AppLocalizations l10n, List<String> actions) {
    final operations = _detail?['operations'] as Map?;
    final primaryCta =
        _detail?['primaryCta'] as String? ??
        operations?['primaryCta'] as String?;
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
    if (primaryCta == 'OPEN_CHAT') {
      return AppUi.primaryButton(
        label: l10n.t('admin_ops_cta_open_chat'),
        icon: Icons.chat_bubble_outline,
        onPressed: _openChat,
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
            label: l10n.t('pickup_datetime'),
            value: detail['scheduledPickupAt'] as String? ?? '-',
          ),
          AppUi.summaryRow(
            label: l10n.t('origin'),
            value: origin['address'] as String? ?? '',
          ),
          AppUi.summaryRow(
            label: l10n.t('destination'),
            value: destination['address'] as String? ?? '',
          ),
          AppUi.summaryRow(
            label: 'Vehicle',
            value: vehicle['typeName'] as String? ?? '-',
          ),
          if (_hasFlight(detail)) ..._flightRows(l10n, detail),
          if (detail['createdAt'] != null)
            AppUi.summaryRow(
              label: l10n.t('admin_detail_created'),
              value: '${detail['createdAt']}',
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
            if (vehicle != null)
              AppUi.summaryRow(
                label: 'Vehicle',
                value: _vehicleSummary(vehicle),
              ),
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
          if (detail['status'] == 'SETTLEMENT_PENDING') ...[
            const Divider(height: 24),
            Text(
              l10n.t('admin_settlement_section'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            _settlementSectionContent(l10n),
          ],
        ],
      ),
    );
  }

  Widget _settlementSectionContent(AppLocalizations l10n) {
    final status = _settlement?['commissionStatus'] as String? ?? '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.summaryRow(
          label: l10n.t('admin_settlement_status'),
          value: status,
        ),
        AppUi.summaryRow(
          label: l10n.t('admin_settlement_transfer_slip'),
          value: _hasTransferSlip
              ? l10n.t('admin_settlement_slip_submitted')
              : l10n.t('admin_settlement_slip_not_submitted'),
        ),
        if (_settlementError != null)
          Text(
            _settlementError!,
            style: const TextStyle(color: AppTokens.error),
          )
        else if (!_hasTransferSlip)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.t('admin_settlement_waiting_slip')),
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

  Widget _chatSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final operations = detail['operations'] as Map?;
    final unread = operations?['adminUnreadCount'] as int? ?? 0;
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_chat'),
      child: Column(
        children: [
          AppUi.summaryRow(
            label: l10n.t('admin_detail_customer_chat'),
            value: unread > 0 ? '$unread' : '-',
          ),
          AppUi.summaryRow(
            label: l10n.t('admin_detail_driver_chat'),
            value: detail['activeAssignment'] is Map
                ? l10n.t('admin_detail_available')
                : '-',
          ),
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.secondaryButton(
            label: l10n.t('admin_ops_cta_open_chat'),
            icon: Icons.chat_bubble_outline,
            onPressed: _openChat,
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _statusHistory(Map<String, dynamic> detail) {
    return (detail['statusHistory'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Widget _activitySection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final history = _statusHistory(detail);
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_detail_status_history'),
      child: Column(
        children: history.map((entry) {
          final from = entry['fromStatus'] as String? ?? '-';
          final to = entry['toStatus'] as String? ?? '-';
          final when = entry['createdAt'] as String? ?? '';
          final role = entry['changedByRole'] as String? ?? '';
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
                          role,
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
