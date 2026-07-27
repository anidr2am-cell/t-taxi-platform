import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import '../../dispatch/data/driver_socket_service.dart';
import 'booking_accept_controller.dart';
import 'booking_display_formatters.dart';
import 'booking_meeting_gate.dart';
import 'booking_status_label.dart';
import 'release_assignment_actions.dart';
import 'release_assignment_ui.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri url);
typedef NameSignPhotoPicker =
    Future<NameSignPhotoFile?> Function(ImageSource source);

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
    this.nameSignPhotoPicker,
  });

  final String bookingNumber;
  final BookingReader repository;
  final Future<void> Function() onUnauthorized;
  final BookingAcceptController? acceptController;
  final ExternalUrlLauncher? externalUrlLauncher;
  final DateTime Function()? now;
  final Stream<DriverSocketEvent>? socketEvents;
  final NameSignPhotoPicker? nameSignPhotoPicker;

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
  bool _uploadingNameSignPhoto = false;
  bool _listRefreshRequested = false;
  bool _closingDetail = false;
  StreamSubscription<DriverSocketEvent>? _socketSubscription;
  Future<List<int>>? _nameSignPhotoLoad;

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
        _closingDetail ||
        event.type != DriverSocketEventType.assignmentReleased) {
      return;
    }
    final bookingNumber = event.payload['bookingNumber']?.toString();
    if (bookingNumber != widget.bookingNumber) return;
    _closeDetail(
      refreshList: true,
      message: assignmentReleasedCloseMessage(event.payload),
    );
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
        _nameSignPhotoLoad = detail.nameSignPhotoUrl == null
            ? null
            : widget.repository.getNameSignPhoto(widget.bookingNumber);
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
      _closeDetail(refreshList: true, message: outcome.message);
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
        _closeDetail(refreshList: true, message: '운행이 종료되었습니다.');
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
    setState(() => _performingAction = true);
    try {
      final released = await confirmReleaseAssignment(
        context: context,
        repository: widget.repository,
        bookingNumber: widget.bookingNumber,
        emergencyOnly: emergencyOnly,
      );
      if (!mounted) return;
      if (!released) {
        setState(() => _performingAction = false);
        return;
      }
      _closeDetail(refreshList: true, message: '배정을 반납했습니다.');
    } on ApiException catch (error) {
      await handleReleaseAssignmentError(
        context: context,
        error: error,
        onUnauthorized: widget.onUnauthorized,
        onReload: _load,
        showMessage: _showMessage,
      );
      if (!mounted) return;
      setState(() => _performingAction = false);
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

  Future<void> _chooseNameSignPhoto() async {
    if (_uploadingNameSignPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              key: const Key('nameSignPhotoCamera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('사진 촬영'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('nameSignPhotoGallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final file = await _pickNameSignPhoto(source);
    if (file == null || !mounted) return;
    await _uploadNameSignPhoto(file);
  }

  Future<NameSignPhotoFile?> _pickNameSignPhoto(ImageSource source) async {
    if (widget.nameSignPhotoPicker case final picker?) {
      return picker(source);
    }
    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return null;
    return NameSignPhotoFile(
      filename: file.name,
      bytes: await file.readAsBytes(),
    );
  }

  Future<void> _uploadNameSignPhoto(NameSignPhotoFile file) async {
    if (_uploadingNameSignPhoto) return;
    setState(() => _uploadingNameSignPhoto = true);
    try {
      final result = await widget.repository.uploadNameSignPhoto(
        widget.bookingNumber,
        file,
      );
      if (!mounted) return;
      final current = _detail;
      setState(() {
        if (current != null) {
          _detail = current.copyWithNameSignPhotoUrl(result.nameSignPhotoUrl);
        }
        _nameSignPhotoLoad = widget.repository.getNameSignPhoto(
          widget.bookingNumber,
        );
        _uploadingNameSignPhoto = false;
        _listRefreshRequested = true;
      });
      _showMessage(
        current?.nameSignPhotoUrl == null
            ? '피켓 사진이 업로드되었습니다.'
            : '피켓 사진이 교체되었습니다.',
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      if (!mounted) return;
      setState(() => _uploadingNameSignPhoto = false);
      _showMessage(_nameSignPhotoErrorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingNameSignPhoto = false);
      _showMessage(const ApiException(ApiFailureKind.unknown).userMessage);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _closeDetail({required bool refreshList, String? message}) {
    if (!mounted || _closingDetail) return;
    _closingDetail = true;
    if (refreshList) _listRefreshRequested = true;
    if (message != null) _showMessage(message);
    Navigator.of(context).pop(_listRefreshRequested);
  }

  void _popWithRefreshFlag() =>
      _closeDetail(refreshList: _listRefreshRequested);

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
            uploadingNameSignPhoto: _uploadingNameSignPhoto,
            nameSignPhotoLoad: _nameSignPhotoLoad,
            onNameSignPhotoPressed: _chooseNameSignPhoto,
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
    required this.uploadingNameSignPhoto,
    required this.nameSignPhotoLoad,
    required this.onNameSignPhotoPressed,
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
  final bool uploadingNameSignPhoto;
  final Future<List<int>>? nameSignPhotoLoad;
  final VoidCallback onNameSignPhotoPressed;
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
    final releaseUi = ReleaseAssignmentUiState.evaluate(
      booking: booking,
      capabilities: detail.capabilities,
      now: now,
    );
    final showPreAcceptChoice = detail.canAccept && releaseUi.releaseRelevant;
    final meetingGate = resolveBkkAirportPickupMeetingGate(
      serviceTypeCode: booking.serviceType.code,
      nameSignRequested: detail.nameSignRequested,
      pickupCandidates: [
        booking.pickupLocation.name,
        booking.pickupLocation.address,
        booking.origin,
      ],
    );
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
        if (showPreAcceptChoice) ...[
          const SizedBox(height: 16),
          PreAcceptReleaseActionCard(
            uiState: releaseUi,
            accepting: accepting,
            performingAction: performingAction,
            onAcceptPressed: onAcceptPressed,
            onReleasePressed: () => onReleasePressed(releaseUi.emergencyOnly),
          ),
        ] else ...[
          if (releaseUi.releaseRelevant) ...[
            const SizedBox(height: 16),
            ReleaseAssignmentDetailSection(
              uiState: releaseUi,
              performingAction: performingAction,
              onReleasePressed: () => onReleasePressed(releaseUi.emergencyOnly),
              prominent:
                  booking.assignmentStatus.isAssigned && !detail.canAccept,
            ),
          ],
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
        const SizedBox(height: 16),
        if (meetingGate != null) ...[
          _MeetingGateBanner(
            gateNumber: meetingGate,
            nameSignRequested: detail.nameSignRequested,
          ),
          const SizedBox(height: 12),
        ],
        if (meetingGate == '3' &&
            _showsNameSignPhotoSection(booking.status.code, detail)) ...[
          _NameSignPhotoSection(
            detail: detail,
            status: booking.status.code,
            uploading: uploadingNameSignPhoto,
            photoLoad: nameSignPhotoLoad,
            onUploadPressed: onNameSignPhotoPressed,
          ),
          const SizedBox(height: 12),
        ],
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

class _MeetingGateBanner extends StatelessWidget {
  const _MeetingGateBanner({
    required this.gateNumber,
    required this.nameSignRequested,
  });

  final String gateNumber;
  final bool nameSignRequested;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = nameSignRequested ? '미팅 장소: 3번 게이트 (피켓 요청됨)' : '미팅 장소: 7번 게이트';
    return Container(
      key: const Key('bkkMeetingGateBanner'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nameSignRequested
            ? colors.primaryContainer
            : colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: nameSignRequested ? colors.primary : colors.tertiary,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            backgroundColor: colors.surface,
            foregroundColor: nameSignRequested
                ? colors.primary
                : colors.tertiary,
            child: Text(
              gateNumber,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: nameSignRequested
                    ? colors.onPrimaryContainer
                    : colors.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _showsNameSignPhotoSection(
  BookingStatusCode status,
  BookingDetail detail,
) =>
    status == BookingStatusCode.onRoute ||
    status == BookingStatusCode.driverArrived ||
    ((status == BookingStatusCode.pickedUp ||
            status == BookingStatusCode.settlementPending ||
            status == BookingStatusCode.completed) &&
        detail.nameSignPhotoUrl != null);

String _nameSignPhotoErrorMessage(ApiException error) =>
    switch (error.errorCode) {
      'VALIDATION_ERROR' => '피켓 사진과 현재 예약 상태를 다시 확인해 주세요.',
      'INVALID_FILE_TYPE' => 'JPG, JPEG, PNG, WEBP 사진만 업로드할 수 있습니다.',
      'FILE_TOO_LARGE' => '파일 크기가 너무 큽니다. 더 작은 사진을 선택해 주세요.',
      'BOOKING_NOT_FOUND' => '예약 정보를 찾을 수 없습니다.',
      'FORBIDDEN' => '이 예약의 피켓 사진을 업로드할 권한이 없습니다.',
      _ when error.kind == ApiFailureKind.forbidden =>
        '이 예약의 피켓 사진을 업로드할 권한이 없습니다.',
      _ => error.userMessage,
    };

class _NameSignPhotoSection extends StatelessWidget {
  const _NameSignPhotoSection({
    required this.detail,
    required this.status,
    required this.uploading,
    required this.photoLoad,
    required this.onUploadPressed,
  });

  final BookingDetail detail;
  final BookingStatusCode status;
  final bool uploading;
  final Future<List<int>>? photoLoad;
  final VoidCallback onUploadPressed;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = detail.nameSignPhotoUrl != null;
    final arrived = status == BookingStatusCode.driverArrived;
    final onRoute = status == BookingStatusCode.onRoute;
    final canUpload = arrived || onRoute;
    return Card(
      key: const Key('nameSignPhotoSection'),
      color: arrived
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasPhoto ? '제출된 피켓 사진' : '피켓 사진 제출',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (detail.nameSignText case final text?) ...[
              const SizedBox(height: 4),
              Text('피켓 문구: $text'),
            ],
            if (onRoute) ...[
              const SizedBox(height: 8),
              const Text(
                '공항 도착 후 촬영을 권장합니다.',
                key: Key('nameSignPhotoOnRouteNotice'),
              ),
            ],
            if (hasPhoto) ...[
              const SizedBox(height: 12),
              FutureBuilder<List<int>>(
                future: photoLoad,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const SizedBox(
                      height: 120,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    );
                  }
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      Uint8List.fromList(bytes),
                      key: const Key('nameSignPhotoPreview'),
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  );
                },
              ),
            ],
            if (canUpload) ...[
              const SizedBox(height: 12),
              if (arrived)
                FilledButton.icon(
                  key: const Key('uploadNameSignPhotoButton'),
                  onPressed: uploading ? null : onUploadPressed,
                  icon: uploading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: Text(hasPhoto ? '다시 촬영/교체' : '피켓 사진 업로드'),
                )
              else
                OutlinedButton.icon(
                  key: const Key('uploadNameSignPhotoButton'),
                  onPressed: uploading ? null : onUploadPressed,
                  icon: uploading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: Text(hasPhoto ? '다시 촬영/교체' : '피켓 사진 업로드'),
                ),
            ] else if (hasPhoto) ...[
              const SizedBox(height: 8),
              const Text(
                '제출된 피켓 사진 보기',
                key: Key('nameSignPhotoViewOnly'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
