import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import '../../dispatch/data/driver_socket_service.dart';
import 'booking_accept_controller.dart';
import 'booking_display_formatters.dart';
import 'booking_meeting_gate.dart';
import 'booking_status_label.dart';
import 'pickup_schedule.dart';
import 'release_assignment_actions.dart';
import 'release_assignment_ui.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri url);
typedef NameSignPhotoPicker =
    Future<NameSignPhotoFile?> Function(ImageSource source);

enum _TripAction {
  startRoute('START_ON_ROUTE'),
  arrive('MARK_ARRIVED'),
  pickedUp('MARK_PICKED_UP'),
  endTrip('END_TRIP');

  const _TripAction(this.serverAction);
  final String serverAction;

  String label(AppLocalizations l10n) => switch (this) {
        _TripAction.startRoute => l10n.tripActionStartRouteLabel,
        _TripAction.arrive => l10n.tripActionArriveLabel,
        _TripAction.pickedUp => l10n.tripActionPickedUpLabel,
        _TripAction.endTrip => l10n.tripActionEndTripLabel,
      };

  String confirmMessage(AppLocalizations l10n) => switch (this) {
        _TripAction.startRoute => l10n.tripActionStartRouteConfirm,
        _TripAction.arrive => l10n.tripActionArriveConfirm,
        _TripAction.pickedUp => l10n.tripActionPickedUpConfirm,
        _TripAction.endTrip => l10n.tripActionEndTripConfirm,
      };
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
      message: assignmentReleasedCloseMessage(
        AppLocalizations.of(context),
        event.payload,
      ),
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
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_accepting,
      builder: (dialogContext) => AlertDialog(
        key: const Key('acceptConfirmDialog'),
        title: Text(l10n.acceptBookingTitle),
        content: Text(l10n.acceptBookingContent),
        actions: [
          TextButton(
            key: const Key('acceptCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('acceptConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.acceptBooking),
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

    final l10n = AppLocalizations.of(context);

    if (outcome.closeDetail) {
      _closeDetail(refreshList: true, message: outcome.localizedMessage(l10n));
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

    _showMessage(outcome.localizedMessage(l10n));
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('tripActionConfirmDialog'),
        title: Text(action.label(l10n)),
        content: Text(action.confirmMessage(l10n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('tripActionConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action.label(l10n)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _runTripAction(action);
  }

  Future<void> _runTripAction(_TripAction action) async {
    if (_performingAction) return;
    setState(() => _performingAction = true);
    final l10n = AppLocalizations.of(context);
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
        _closeDetail(refreshList: true, message: l10n.tripEndedMessage);
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
      _showMessage(l10n.actionCompleted(action.label(l10n)));
    } on ApiException catch (error) {
      await _handleActionError(error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _performingAction = false);
      _showMessage(
        const ApiException(ApiFailureKind.unknown).localizedMessage(l10n),
      );
    }
  }

  Future<void> _handleActionError(ApiException error) async {
    if (error.kind == ApiFailureKind.unauthorized) {
      await widget.onUnauthorized();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _performingAction = false);
    _showMessage(error.localizedMessage(l10n));
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
      _closeDetail(
        refreshList: true,
        message: AppLocalizations.of(context).assignmentReleasedSuccess,
      );
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
      _showMessage(
        const ApiException(
          ApiFailureKind.unknown,
        ).localizedMessage(AppLocalizations.of(context)),
      );
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
    final l10n = AppLocalizations.of(context);
    try {
      final opened = await (widget.externalUrlLauncher ?? launchUrl)(url);
      if (!opened) _showMessage(l10n.cannotOpenMapsApp);
    } catch (_) {
      _showMessage(l10n.cannotOpenMapsApp);
    }
  }

  Future<void> _chooseNameSignPhoto() async {
    if (_uploadingNameSignPhoto) return;
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              key: const Key('nameSignPhotoCamera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.takePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('nameSignPhotoGallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.pickFromGallery),
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
    final l10n = AppLocalizations.of(context);
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
            ? l10n.nameSignPhotoUploaded
            : l10n.nameSignPhotoReplaced,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      if (!mounted) return;
      setState(() => _uploadingNameSignPhoto = false);
      _showMessage(nameSignUploadErrorMessage(l10n, error.errorCode));
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingNameSignPhoto = false);
      _showMessage(
        const ApiException(ApiFailureKind.unknown).localizedMessage(l10n),
      );
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
          title: Text(AppLocalizations.of(context).bookingDetailTitle),
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
    final l10n = AppLocalizations.of(context);
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
                  ? l10n.bookingNoLongerVisible
                  : error.localizedMessage(l10n),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (unavailable)
              OutlinedButton(
                key: const Key('detailBackButton'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.backToList),
              )
            else
              FilledButton(
                key: const Key('detailRetryButton'),
                onPressed: onRetry,
                child: Text(l10n.retry),
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
    final l10n = AppLocalizations.of(context);
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
    final meetingGateInfo = buildMeetingGateInfo(
      serviceTypeCode: booking.serviceType.code,
      nameSignRequested: detail.nameSignRequested,
      nameSignText: booking.nameSignText,
      pickupCandidates: [
        booking.pickupLocation.name,
        booking.pickupLocation.address,
        booking.origin,
      ],
    );
    final pickupDelay = pickupDelayInfo(
      scheduledPickupAt: booking.scheduledPickupAt,
      pickupDate: booking.pickupDate,
      pickupTime: booking.pickupTime,
      now: () => now,
    );
    final pickupDelayMessage = pickupDelay == null
        ? null
        : pickupDelayBannerMessage(l10n, pickupDelay);
    return ListView(
      key: const Key('detailSuccess'),
      padding: const EdgeInsets.all(16),
      children: [
        if (pickupDelayMessage case final message?)
          MaterialBanner(
            key: const Key('pickupDelayBanner'),
            content: Text(message),
            leading: const Icon(Icons.info_outline),
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            actions: const [SizedBox.shrink()],
          ),
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
                  : Text(l10n.acceptBooking),
            ),
          ] else if (waitingForStandby) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('standbyPendingButton'),
              onPressed: null,
              child: Text(l10n.standbyConfirmPending),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.standbyAllowedFrom(standbyAllowedAt ?? ''),
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
                : Text(action.label(l10n)),
          ),
        ],
        const SizedBox(height: 16),
        if (meetingGateInfo != null) ...[
          _MeetingGateBanner(
            gateInfo: meetingGateInfo,
            nameSignRequested: detail.nameSignRequested,
          ),
          const SizedBox(height: 12),
        ],
        if (meetingGateInfo?.gateNumber == '3' &&
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
          title: l10n.sectionTripInfo,
          children: [
            _Info(
              label: l10n.labelPickup,
              value: '${booking.pickupDate} ${booking.pickupTime}',
            ),
            if (formatBookingCreatedAtLabel(l10n, booking.createdAt)
                case final label?)
              Padding(
                padding: const EdgeInsets.only(left: 104, bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    key: const Key('bookingCreatedAtLabel'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            _LocationInfo(
              label: l10n.labelOrigin,
              location: booking.pickupLocation,
              fallback: booking.origin,
              onOpenMap: onOpenMap,
              mapKey: const Key('pickupMapLink'),
            ),
            _LocationInfo(
              label: l10n.labelDestination,
              location: booking.destinationLocation,
              fallback: booking.destination,
              onOpenMap: onOpenMap,
              mapKey: const Key('destinationMapLink'),
            ),
          ],
        ),
        _Section(
          title: l10n.sectionCustomerAndPassengers,
          children: [
            _Info(label: l10n.labelCustomerName, value: booking.customerDisplayName),
            _Info(
              label: l10n.labelTotalPassengers,
              value: booking.passengerCount == null
                  ? null
                  : l10n.passengersCount(booking.passengerCount!),
            ),
            _Info(
              label: l10n.labelPassengerComposition,
              value: detail.passengers.displayLocalized(l10n),
            ),
            _Info(
              label: l10n.labelLuggage,
              value: detail.luggage.displayLocalized(l10n),
            ),
            if (detail.nameSignRequested)
              _Info(label: l10n.labelNameboard, value: l10n.nameboardRequested),
          ],
        ),
        _Section(
          title: l10n.sectionFlightAndVehicle,
          children: [
            _Info(
              label: l10n.labelFlight,
              value: flight.flightNumber ?? booking.flightNumber,
            ),
            _Info(label: l10n.labelFlightStatus, value: flight.flightStatus),
            _Info(
              label: l10n.labelEstimatedArrival,
              value: flight.latestEstimatedArrival,
            ),
            _Info(
              label: l10n.labelDelay,
              value: flight.delayMinutes == null
                  ? null
                  : l10n.delayMinutes(flight.delayMinutes!),
            ),
            _Info(label: l10n.labelVehicle, value: vehicle.isEmpty ? null : vehicle),
          ],
        ),
        _Section(
          title: l10n.sectionAmountInfo,
          children: [
            _Info(
              label: l10n.labelCustomerPaymentAmount,
              value: formatMoneyLocalized(l10n, detail.customerPayment),
            ),
            _Info(
              label: l10n.labelCompanyCommission,
              value: formatMoneyLocalized(l10n, detail.companyCommission),
            ),
            _Info(
              label: l10n.labelDriverExpectedIncome,
              value: formatMoneyLocalized(l10n, booking.driverExpectedIncome),
            ),
          ],
        ),
        if (detail.specialInstructions case final instructions?)
          _Section(
            title: l10n.sectionDriverNotes,
            children: [
              _Info(label: l10n.labelCustomerRequest, value: instructions),
            ],
          ),
      ],
    );
  }
}

class _MeetingGateBanner extends StatelessWidget {
  static const _nameSignTextLabel = 'ชื่อป้ายที่ต้องเขียน:';

  const _MeetingGateBanner({
    required this.gateInfo,
    required this.nameSignRequested,
  });

  final MeetingGateInfo gateInfo;
  final bool nameSignRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = nameSignRequested
        ? l10n.meetingPlaceGate3WithNameSign
        : l10n.meetingPlaceGate7;
    final nameSignText = gateInfo.nameSignText;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: colors.surface,
            foregroundColor: nameSignRequested
                ? colors.primary
                : colors.tertiary,
            child: Text(
              gateInfo.gateNumber,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: nameSignRequested
                        ? colors.onPrimaryContainer
                        : colors.onTertiaryContainer,
                  ),
                ),
                if (nameSignText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _nameSignTextLabel,
                    key: const Key('bkkMeetingGateNameSignLabel'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: nameSignRequested
                          ? colors.onPrimaryContainer
                          : colors.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nameSignText,
                    key: const Key('bkkMeetingGateNameSignText'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: nameSignRequested
                          ? colors.onPrimaryContainer
                          : colors.onTertiaryContainer,
                    ),
                  ),
                ],
              ],
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
    final l10n = AppLocalizations.of(context);
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
              hasPhoto ? l10n.submittedNameSignPhoto : l10n.submitNameSignPhoto,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (detail.nameSignText case final text?) ...[
              const SizedBox(height: 4),
              Text(l10n.nameSignTextLabel(text)),
            ],
            if (onRoute) ...[
              const SizedBox(height: 8),
              Text(
                l10n.recommendPhotoAfterAirportArrival,
                key: const Key('nameSignPhotoOnRouteNotice'),
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
                  label: Text(
                    hasPhoto
                        ? l10n.retakeOrReplacePhoto
                        : l10n.uploadNameSignPhoto,
                  ),
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
                  label: Text(
                    hasPhoto
                        ? l10n.retakeOrReplacePhoto
                        : l10n.uploadNameSignPhoto,
                  ),
                ),
            ] else if (hasPhoto) ...[
              const SizedBox(height: 8),
              Text(
                l10n.viewSubmittedNameSignPhoto,
                key: const Key('nameSignPhotoViewOnly'),
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
    final l10n = AppLocalizations.of(context);
    final formatted = formatBookingLocation(l10n, location);
    final fallbackText = fallback.trim();
    final value = formatted == l10n.noLocationInfo && fallbackText.isNotEmpty
        ? fallbackText
        : formatted;
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
                    label: Text(l10n.viewOnMap),
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
