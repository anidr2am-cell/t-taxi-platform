import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import '../../dispatch/data/driver_socket_service.dart';
import 'booking_accept_controller.dart';
import 'booking_display_formatters.dart';
import 'booking_status_label.dart';
import 'release_assignment_dialog.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri url);

enum _TripAction {
  startRoute('START_ON_ROUTE', '운행 시작', '운행을 시작하시겠습니까?'),
  arrive('MARK_ARRIVED', '도착 확인', '픽업 장소 도착을 확인하시겠습니까?'),
  pickedUp('MARK_PICKED_UP', '탑승 확인', '고객 탑승을 확인하시겠습니까?'),
  endTrip('END_TRIP', '운행 종료', '운행을 종료하시겠습니까?');

  const _TripAction(this.serverAction, this.label, this.confirmMessage);
  final String serverAction;
  final String label;
  final String confirmMessage;
}

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.bookingNumber,
    required this.repository,
    required this.onUnauthorized,
    this.acceptController,
    this.externalUrlLauncher,
    this.now,
    this.socketEvents,
  });

  final String bookingNumber;
  final BookingReader repository;
  final Future<void> Function() onUnauthorized;
  final BookingAcceptController? acceptController;
  final ExternalUrlLauncher? externalUrlLauncher;
  final DateTime Function()? now;
  final Stream<DriverSocketEvent>? socketEvents;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late final BookingAcceptController _acceptController;
  BookingDetail? _detail;
  ApiException? _error;
  bool _loading = true;
  bool _accepting = false;
  bool _performingAction = false;
  bool _listRefreshRequested = false;
  bool _handlingSocketRelease = false;
  StreamSubscription<DriverSocketEvent>? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _acceptController =
        widget.acceptController ?? BookingAcceptController(widget.repository);
    _listenToSocketEvents();
    _load();
  }

  void _listenToSocketEvents() {
    _socketSubscription?.cancel();
    _socketSubscription = widget.socketEvents?.listen(_handleSocketEvent);
  }

  void _handleSocketEvent(DriverSocketEvent event) {
    if (!mounted ||
        _handlingSocketRelease ||
        event.type != DriverSocketEventType.assignmentReleased) {
      return;
    }
    final bookingNumber = event.payload['bookingNumber']?.toString();
    if (bookingNumber != widget.bookingNumber) return;
    _handlingSocketRelease = true;
    _listRefreshRequested = true;
    _showMessage('이 예약의 배정이 종료되어 목록으로 돌아갑니다.');
    Navigator.of(context).pop(true);
  }

  @override
  void didUpdateWidget(covariant BookingDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingNumber != widget.bookingNumber ||
        oldWidget.repository != widget.repository) {
      _load();
    }
    if (oldWidget.socketEvents != widget.socketEvents) {
      _listenToSocketEvents();
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.getBookingDetail(
        widget.bookingNumber,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _detail = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _detail = null;
        _loading = false;
      });
    }
  }

  Future<void> _confirmAccept() async {
    final detail = _detail;
    if (detail == null || !detail.canAccept || _accepting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_accepting,
      builder: (dialogContext) => AlertDialog(
        key: const Key('acceptConfirmDialog'),
        title: const Text('예약 수락'),
        content: const Text('이 예약을 수락하시겠습니까?'),
        actions: [
          TextButton(
            key: const Key('acceptCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('acceptConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('예약 수락'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runAccept(detail);
  }

  Future<void> _runAccept(BookingDetail detail) async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final outcome = await _acceptController.accept(
      bookingNumber: widget.bookingNumber,
      currentDetail: detail,
    );

    if (!mounted) return;

    if (outcome.refreshList) {
      _listRefreshRequested = true;
    }

    if (outcome.expireAuth) {
      await widget.onUnauthorized();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (outcome.closeDetail) {
      _showMessage(outcome.message);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    setState(() {
      _accepting = false;
      if (outcome.detail != null) {
        _detail = outcome.detail;
        _error = null;
        _loading = false;
      }
    });

    _showMessage(outcome.message);
  }

  _TripAction? _availableTripAction(BookingDetail detail) {
    final booking = detail.summary;
    return switch (booking.status.code) {
      BookingStatusCode.driverAssigned
          when booking.assignmentStatus.isAccepted &&
              booking.allowsAction('START_ON_ROUTE') =>
        _TripAction.startRoute,
      BookingStatusCode.onRoute when booking.allowsAction('MARK_ARRIVED') =>
        _TripAction.arrive,
      BookingStatusCode.driverArrived
          when booking.allowsAction('MARK_PICKED_UP') =>
        _TripAction.pickedUp,
      BookingStatusCode.pickedUp when booking.allowsAction('END_TRIP') =>
        _TripAction.endTrip,
      _ => null,
    };
  }

  Future<void> _confirmTripAction(_TripAction action) async {
    if (_performingAction) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('tripActionConfirmDialog'),
        title: Text(action.label),
        content: Text(action.confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('tripActionConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _runTripAction(action);
  }

  Future<void> _runTripAction(_TripAction action) async {
    if (_performingAction) return;
    setState(() => _performingAction = true);
    try {
      switch (action) {
        case _TripAction.startRoute:
          await widget.repository.startOnRoute(widget.bookingNumber);
        case _TripAction.arrive:
          await widget.repository.markArrived(widget.bookingNumber);
        case _TripAction.pickedUp:
          await widget.repository.markPickedUp(widget.bookingNumber);
        case _TripAction.endTrip:
          await widget.repository.endTrip(widget.bookingNumber);
      }
      if (!mounted) return;
      _listRefreshRequested = true;
      if (action == _TripAction.endTrip) {
        _showMessage('운행이 종료되었습니다.');
        Navigator.of(context).pop(true);
        return;
      }
      final refreshed = await widget.repository.getBookingDetail(
        widget.bookingNumber,
      );
      if (!mounted) return;
      setState(() {
        _detail = refreshed;
        _performingAction = false;
      });
      _showMessage('${action.label} 처리가 완료되었습니다.');
    } on ApiException catch (error) {
      await _handleActionError(error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _performingAction = false);
      _showMessage(const ApiException(ApiFailureKind.unknown).userMessage);
    }
  }

  Future<void> _handleActionError(ApiException error) async {
    if (error.kind == ApiFailureKind.unauthorized) {
      await widget.onUnauthorized();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (!mounted) return;
    setState(() => _performingAction = false);
    _showMessage(error.userMessage);
    if (error.kind == ApiFailureKind.invalidStatusTransition ||
        error.kind == ApiFailureKind.bookingNotAssigned ||
        error.kind == ApiFailureKind.assignmentAlreadyReleased) {
      await _load();
    }
  }

  Future<void> _confirmRelease(bool emergencyOnly) async {
    if (_performingAction) return;
    final input = await showDialog<ReleaseAssignmentInput>(
      context: context,
      builder: (_) => ReleaseAssignmentDialog(emergencyOnly: emergencyOnly),
    );
    if (input == null || !mounted) return;
    setState(() => _performingAction = true);
    try {
      await widget.repository.releaseAssignment(
        widget.bookingNumber,
        reasonCode: input.reasonCode,
        reasonDetail: input.reasonDetail,
      );
      if (!mounted) return;
      _showMessage('배정을 반납했습니다.');
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      await _handleActionError(error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _performingAction = false);
      _showMessage(const ApiException(ApiFailureKind.unknown).userMessage);
    }
  }

  Future<void> _openMap(BookingLocation location) async {
    final latitude = location.latitude;
    final longitude = location.longitude;
    if (latitude == null || longitude == null) return;
    final url = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    try {
      final opened = await (widget.externalUrlLauncher ?? launchUrl)(url);
      if (!opened) _showMessage('지도 앱을 열 수 없습니다.');
    } catch (_) {
      _showMessage('지도 앱을 열 수 없습니다.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _popWithRefreshFlag() {
    Navigator.of(context).pop(_listRefreshRequested);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithRefreshFlag();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('예약 상세'),
          leading: BackButton(onPressed: _popWithRefreshFlag),
        ),
        body: switch ((_loading, _detail, _error)) {
          (true, _, _) => const Center(
            key: Key('detailLoading'),
            child: CircularProgressIndicator(),
          ),
          (false, _, final error?) => _DetailError(
            error: error,
            onRetry: _load,
          ),
          (false, final detail?, _) => _DetailBody(
            detail: detail,
            accepting: _accepting,
            performingAction: _performingAction,
            tripAction: _availableTripAction(detail),
            onAcceptPressed: _confirmAccept,
            onTripActionPressed: _confirmTripAction,
            onReleasePressed: _confirmRelease,
            onOpenMap: _openMap,
            now: (widget.now ?? DateTime.now)(),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final unavailable =
        error.kind == ApiFailureKind.notFound ||
        error.errorCode == 'BOOKING_NOT_FOUND';
    return Center(
      key: const Key('detailError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unavailable
                  ? Icons.event_busy_outlined
                  : Icons.cloud_off_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              unavailable
                  ? '이 예약은 더 이상 배정 내역에서 확인할 수 없습니다.'
                  : error.userMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (unavailable)
              OutlinedButton(
                key: const Key('detailBackButton'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('목록으로 돌아가기'),
              )
            else
              FilledButton(
                key: const Key('detailRetryButton'),
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.accepting,
    required this.performingAction,
    required this.tripAction,
    required this.onAcceptPressed,
    required this.onTripActionPressed,
    required this.onReleasePressed,
    required this.onOpenMap,
    required this.now,
  });

  final BookingDetail detail;
  final bool accepting;
  final bool performingAction;
  final _TripAction? tripAction;
  final VoidCallback onAcceptPressed;
  final ValueChanged<_TripAction> onTripActionPressed;
  final ValueChanged<bool> onReleasePressed;
  final ValueChanged<BookingLocation> onOpenMap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final booking = detail.summary;
    final vehicle = booking.vehicleType.name.isNotEmpty
        ? booking.vehicleType.name
        : booking.vehicleType.code;
    final flight = detail.flight;
    final standbyAllowedAt = formatBookingDateTime(booking.standbyAllowedAt);
    final waitingForStandby =
        booking.status.code == BookingStatusCode.driverAssigned &&
        booking.assignmentStatus.isAssigned &&
        booking.standbyAllowedAt != null &&
        !booking.canConfirmStandby;
    final capabilities = detail.capabilities;
    final deadline = DateTime.tryParse(
      capabilities.assignmentReleaseDeadline ?? '',
    );
    final deadlinePassed = deadline != null && !now.isBefore(deadline);
    final emergencyOnly = capabilities.releaseAssignmentEmergencyOnly;
    final releaseActionAllowed = booking.allowsAction('RELEASE_ASSIGNMENT');
    final releaseEnabled =
        releaseActionAllowed &&
        (capabilities.releaseAssignmentAvailable || emergencyOnly) &&
        (!deadlinePassed || emergencyOnly) &&
        (capabilities.assignmentReleaseBlockedReason == null ||
            capabilities.assignmentReleaseBlockedReason == 'WITHIN_TWO_HOURS');
    final releaseRelevant =
        releaseActionAllowed &&
        (releaseEnabled ||
            deadlinePassed ||
            capabilities.assignmentReleaseBlockedReason != null);
    return ListView(
      key: const Key('detailSuccess'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                booking.bookingNumber,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            BookingStatusLabel(status: booking.status),
          ],
        ),
        if (detail.canAccept) ...[
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('acceptBookingButton'),
            onPressed: accepting ? null : onAcceptPressed,
            child: accepting
                ? const SizedBox(
                    key: Key('acceptBookingLoading'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('예약 수락'),
          ),
        ] else if (waitingForStandby) ...[
          const SizedBox(height: 16),
          const FilledButton(
            key: Key('standbyPendingButton'),
            onPressed: null,
            child: Text('대기 확정 대기'),
          ),
          const SizedBox(height: 8),
          Text(
            '$standbyAllowedAt부터 대기 확정 가능',
            key: const Key('standbyAllowedAtNotice'),
            textAlign: TextAlign.center,
          ),
        ],
        if (tripAction case final action?) ...[
          const SizedBox(height: 12),
          FilledButton(
            key: Key('tripAction-${action.serverAction}'),
            onPressed: performingAction
                ? null
                : () => onTripActionPressed(action),
            child: performingAction
                ? const SizedBox(
                    key: Key('tripActionLoading'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(action.label),
          ),
        ],
        if (releaseRelevant) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('releaseAssignmentButton'),
            onPressed: releaseEnabled && !performingAction
                ? () => onReleasePressed(emergencyOnly)
                : null,
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('배정 반납'),
          ),
          if (emergencyOnly)
            const Text(
              '일반 반납 가능 시간이 지났습니다. 긴급 사유로만 반납할 수 있습니다.',
              key: Key('releaseEmergencyOnlyNotice'),
              textAlign: TextAlign.center,
            )
          else if (capabilities.assignmentReleaseBlockedReason
              case final reason?)
            Text(
              _releaseBlockedMessage(reason),
              key: const Key('releaseBlockedNotice'),
              textAlign: TextAlign.center,
            )
          else if (deadlinePassed)
            const Text(
              '배정 반납 가능 시간이 지났습니다.',
              key: Key('releaseDeadlineNotice'),
              textAlign: TextAlign.center,
            ),
        ],
        const SizedBox(height: 16),
        _Section(
          title: '운행 정보',
          children: [
            _Info(
              label: '픽업',
              value: '${booking.pickupDate} ${booking.pickupTime}',
            ),
            _LocationInfo(
              label: '출발지',
              location: booking.pickupLocation,
              fallback: booking.origin,
              onOpenMap: onOpenMap,
              mapKey: const Key('pickupMapLink'),
            ),
            _LocationInfo(
              label: '목적지',
              location: booking.destinationLocation,
              fallback: booking.destination,
              onOpenMap: onOpenMap,
              mapKey: const Key('destinationMapLink'),
            ),
          ],
        ),
        _Section(
          title: '고객 및 탑승 정보',
          children: [
            _Info(label: '고객명', value: booking.customerDisplayName),
            _Info(
              label: '총 인원',
              value: booking.passengerCount == null
                  ? null
                  : '${booking.passengerCount}명',
            ),
            _Info(label: '구성', value: detail.passengers.display),
            _Info(label: '수하물', value: detail.luggage.display),
            if (detail.nameSignRequested)
              const _Info(label: '네임보드', value: '요청됨'),
          ],
        ),
        _Section(
          title: '항공편 및 차량',
          children: [
            _Info(
              label: '항공편',
              value: flight.flightNumber ?? booking.flightNumber,
            ),
            _Info(label: '항공편 상태', value: flight.flightStatus),
            _Info(label: '도착 예정', value: flight.latestEstimatedArrival),
            _Info(
              label: '지연',
              value: flight.delayMinutes == null
                  ? null
                  : '${flight.delayMinutes}분',
            ),
            _Info(label: '차량', value: vehicle.isEmpty ? null : vehicle),
          ],
        ),
        _Section(
          title: '금액 정보',
          children: [
            _Info(
              label: '고객 결제 금액',
              value: formatMoney(detail.customerPayment),
            ),
            _Info(
              label: '회사 수수료',
              value: formatMoney(detail.companyCommission),
            ),
            _Info(
              label: '기사 예상 수입',
              value: formatMoney(booking.driverExpectedIncome),
            ),
          ],
        ),
        if (detail.specialInstructions case final instructions?)
          _Section(
            title: '기사 참고 사항',
            children: [_Info(label: '고객 요청', value: instructions)],
          ),
      ],
    );
  }
}

String _releaseBlockedMessage(String reason) => switch (reason) {
  'TRIP_ALREADY_STARTED' => '운행이 시작되어 배정을 반납할 수 없습니다.',
  'NO_ACTIVE_ASSIGNMENT' => '활성 배정이 없어 반납할 수 없습니다.',
  'NOT_ASSIGNED_DRIVER' => '현재 기사에게 배정된 예약이 아닙니다.',
  'BOOKING_TERMINAL_STATUS' => '종료된 예약은 반납할 수 없습니다.',
  'INVALID_PICKUP_TIME' => '픽업 시간을 확인할 수 없어 반납할 수 없습니다.',
  'WITHIN_TWO_HOURS' => '일반 반납 가능 시간이 지났습니다.',
  _ => '현재 이 배정을 반납할 수 없습니다.',
};

class _LocationInfo extends StatelessWidget {
  const _LocationInfo({
    required this.label,
    required this.location,
    required this.fallback,
    required this.onOpenMap,
    required this.mapKey,
  });

  final String label;
  final BookingLocation location;
  final String fallback;
  final ValueChanged<BookingLocation> onOpenMap;
  final Key mapKey;

  @override
  Widget build(BuildContext context) {
    final name = location.name;
    final address = location.address;
    final parts = <String>[
      ?name,
      if (address != null && address != name) address,
    ];
    final value = parts.isEmpty ? fallback : parts.join('\n');
    final hasCoordinates =
        location.latitude != null && location.longitude != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value),
                if (hasCoordinates)
                  TextButton.icon(
                    key: mapKey,
                    onPressed: () => onOpenMap(location),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 36),
                    ),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('지도에서 보기'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final display = value?.trim();
    if (display == null || display.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label)),
          Expanded(child: Text(display)),
        ],
      ),
    );
  }
}
