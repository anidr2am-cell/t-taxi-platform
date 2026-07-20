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
  serverError,
}

class BookingAcceptOutcome {
  const BookingAcceptOutcome({
    required this.kind,
    required this.message,
    this.detail,
    this.refreshList = false,
    this.closeDetail = false,
    this.expireAuth = false,
  });

  final BookingAcceptOutcomeKind kind;
  final String message;
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
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '이미 예약 수락을 처리 중입니다.',
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
        message: const ApiException(ApiFailureKind.unknown).userMessage,
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
        message: '예약을 수락했습니다.',
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return const BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          message: '로그인이 만료되었습니다. 다시 로그인해 주세요.',
          expireAuth: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.success,
        message: '예약을 수락했습니다.',
        detail: optimistic,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.success,
        message: '예약을 수락했습니다.',
        detail: optimistic,
        refreshList: true,
      );
    }
  }

  Future<BookingAcceptOutcome> _mapApiException(
    ApiException error, {
    required String bookingNumber,
    required BookingDetail currentDetail,
  }) async {
    switch (error.kind) {
      case ApiFailureKind.unauthorized:
        return const BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          message: '로그인이 만료되었습니다. 다시 로그인해 주세요.',
          expireAuth: true,
        );
      case ApiFailureKind.forbidden:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.forbidden,
          message: error.userMessage,
          detail: currentDetail,
        );
      case ApiFailureKind.notFound:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.notFound,
          message: '예약 정보를 찾을 수 없습니다. 예약 목록을 새로고침했습니다.',
          refreshList: true,
          closeDetail: true,
        );
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
      case ApiFailureKind.configuration:
      case ApiFailureKind.unknown:
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.serverError,
          message: error.userMessage,
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
          message: '예약을 수락했습니다.',
          detail: refreshed,
          refreshList: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.conflictUpdated,
        message: '예약 상태가 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return const BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          message: '로그인이 만료되었습니다. 다시 로그인해 주세요.',
          expireAuth: true,
        );
      }
      if (error.kind == ApiFailureKind.notFound) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.notFound,
          message: '예약 정보를 찾을 수 없습니다. 예약 목록을 새로고침했습니다.',
          refreshList: true,
          closeDetail: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
        detail: currentDetail,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
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
          message: '예약을 수락했습니다.',
          detail: refreshed,
          refreshList: true,
        );
      }
      if (refreshed.summary.assignmentStatus.isAssigned) {
        return BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.stillAssigned,
          message: '예약이 아직 수락되지 않았습니다. 상태를 확인한 뒤 다시 시도해 주세요.',
          detail: refreshed,
          refreshList: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
        detail: refreshed,
        refreshList: true,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return const BookingAcceptOutcome(
          kind: BookingAcceptOutcomeKind.unauthorized,
          message: '로그인이 만료되었습니다. 다시 로그인해 주세요.',
          expireAuth: true,
        );
      }
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
        detail: currentDetail,
        refreshList: true,
      );
    } catch (_) {
      return BookingAcceptOutcome(
        kind: BookingAcceptOutcomeKind.uncertain,
        message: '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
        detail: currentDetail,
        refreshList: true,
      );
    }
  }
}
