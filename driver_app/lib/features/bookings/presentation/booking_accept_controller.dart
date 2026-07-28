import '../../../core/network/api_exception.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';

enum BookingAcceptOutcomeKind {
  success,
  unauthorized,
  forbidden,
  notFound,
  conflictUpdated,
  stillAssigned,
  uncertain,
  alreadyAccepting,
  serverError,
}

class BookingAcceptOutcome {
  const BookingAcceptOutcome({
    required this.kind,
    this.error,
    this.detail,
    this.refreshList = false,
    this.closeDetail = false,
    this.expireAuth = false,
  });

  final BookingAcceptOutcomeKind kind;
  final ApiException? error;
  final BookingDetail? detail;
  final bool refreshList;
  final bool closeDetail;
  final bool expireAuth;
}

/// Orchestrates a single booking accept attempt with timeout-safe recovery.
class BookingAcceptController {
  BookingAcceptController(this._repository);

  final BookingReader _repository;

  bool _inFlight = false;

  bool get isAccepting => _inFlight;

  Future<BookingAcceptOutcome> accept({
    required String bookingNumber,
    required BookingDetail currentDetail,
  }) async {
    if (_inFlight) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.alreadyAccepting,
        detail: currentDetail,
      );
    }

    _inFlight = true;
    try {
      final acceptance = await _repository.acceptBooking(bookingNumber);
      return await _completeSuccess(
        bookingNumber: bookingNumber,
        currentDetail: currentDetail,
        acceptance: acceptance,
      );
    } on ApiException catch (error) {
      return _mapApiException(
        error,
        bookingNumber: bookingNumber,
        currentDetail: currentDetail,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.serverError,
        error: const ApiException(ApiFailureKind.unknown),
        detail: currentDetail,
      );
    } finally {
      _inFlight = false;
    }
  }

  Future<BookingAcceptOutcome> _completeSuccess({
    required String bookingNumber,
    required BookingDetail currentDetail,
    required BookingAcceptance acceptance,
  }) async {
    if (!_isValidAcceptance(bookingNumber, acceptance)) {
      return _recoverAfterUncertainPost(
        bookingNumber: bookingNumber,
        currentDetail: currentDetail,
      );
    }

    final optimistic = currentDetail.copyWithSummary(
      currentDetail.summary.copyWith(
        status: acceptance.bookingStatus,
        assignmentStatus: acceptance.assignmentStatus,
      ),
    );

    try {
      final refreshed = await _repository.getBookingDetail(bookingNumber);
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.success,
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          expireAuth: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.success,
        detail: optimistic,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.success,
        detail: optimistic,
        refreshList: true,
      );
    }
  }

  bool _isValidAcceptance(String bookingNumber, BookingAcceptance acceptance) {
    return acceptance.bookingNumber == bookingNumber &&
        acceptance.assignmentStatus.isAccepted &&
        acceptance.bookingStatus.code == BookingStatusCode.driverAssigned;
  }

  Future<BookingAcceptOutcome> _mapApiException(
    ApiException error, {
    required String bookingNumber,
    required BookingDetail currentDetail,
  }) async {
    switch (error.kind) {
      case ApiFailureKind.unauthorized:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          expireAuth: true,
        );
      case ApiFailureKind.forbidden:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.forbidden,
          error: error,
          detail: currentDetail,
        );
      case ApiFailureKind.notFound:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.notFound,
          refreshList: true,
          closeDetail: true,
        );
      case ApiFailureKind.standbyTooEarly:
      case ApiFailureKind.standbyReferenceTimeMissing:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.stillAssigned,
          error: error,
          detail: currentDetail,
        );
      case ApiFailureKind.bookingTimeConflict:
      case ApiFailureKind.alreadyClaimed:
      case ApiFailureKind.invalidStatusTransition:
      case ApiFailureKind.releaseNotAllowed:
      case ApiFailureKind.assignmentAlreadyReleased:
      case ApiFailureKind.bookingNotAssigned:
      case ApiFailureKind.conflict:
        return _recoverAfterConflict(
          bookingNumber: bookingNumber,
          currentDetail: currentDetail,
        );
      case ApiFailureKind.timeout:
      case ApiFailureKind.unavailable:
        return _recoverAfterUncertainPost(
          bookingNumber: bookingNumber,
          currentDetail: currentDetail,
        );
      case ApiFailureKind.server:
      case ApiFailureKind.invalidResponse:
      case ApiFailureKind.invalidCredentials:
      case ApiFailureKind.validation:
      case ApiFailureKind.invalidFileType:
      case ApiFailureKind.fileTooLarge:
      case ApiFailureKind.settlementNotFound:
      case ApiFailureKind.receiptAlreadyApproved:
      case ApiFailureKind.driverNotEligible:
      case ApiFailureKind.vehiclePlateAlreadyRegistered:
      case ApiFailureKind.urgentAlreadyLocked:
      case ApiFailureKind.urgentNotUrgentBooking:
      case ApiFailureKind.urgentNotBroadcasting:
      case ApiFailureKind.urgentEtaInvalid:
      case ApiFailureKind.urgentEtaExceedsPickupWindow:
      case ApiFailureKind.urgentNotLockedDriver:
      case ApiFailureKind.urgentNegotiationNotFound:
      case ApiFailureKind.urgentNotLocked:
      case ApiFailureKind.urgentEtaExpired:
      case ApiFailureKind.urgentEtaNotFastEnough:
      case ApiFailureKind.configuration:
      case ApiFailureKind.unknown:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.serverError,
          error: error,
          detail: currentDetail,
        );
    }
  }

  Future<BookingAcceptOutcome> _recoverAfterConflict({
    required String bookingNumber,
    required BookingDetail currentDetail,
  }) async {
    try {
      final refreshed = await _repository.getBookingDetail(bookingNumber);
      if (refreshed.summary.assignmentStatus.isAccepted) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.success,
          detail: refreshed,
          refreshList: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.conflictUpdated,
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          expireAuth: true,
        );
      }
      if (error.kind == ApiFailureKind.notFound) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.notFound,
          refreshList: true,
          closeDetail: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        detail: currentDetail,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        detail: currentDetail,
        refreshList: true,
      );
    }
  }

  Future<BookingAcceptOutcome> _recoverAfterUncertainPost({
    required String bookingNumber,
    required BookingDetail currentDetail,
  }) async {
    try {
      final refreshed = await _repository.getBookingDetail(bookingNumber);
      if (refreshed.summary.assignmentStatus.isAccepted) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.success,
          detail: refreshed,
          refreshList: true,
        );
      }
      if (refreshed.summary.assignmentStatus.isAssigned) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.stillAssigned,
          detail: refreshed,
          refreshList: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          expireAuth: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        detail: currentDetail,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        detail: currentDetail,
        refreshList: true,
      );
    }
  }
}
