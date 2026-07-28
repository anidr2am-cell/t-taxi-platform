import '../../core/network/api_exception.dart';
import '../../features/bookings/data/booking_models.dart';
import '../../features/bookings/presentation/booking_accept_controller.dart';
import '../../features/settlement/data/settlement_models.dart';
import 'app_localizations.dart';

extension ApiExceptionLocalization on ApiException {
  String localizedMessage(AppLocalizations l10n) => switch (kind) {
        ApiFailureKind.invalidCredentials => l10n.errorInvalidCredentials,
        ApiFailureKind.unauthorized => l10n.errorUnauthorized,
        ApiFailureKind.forbidden => l10n.errorForbidden,
        ApiFailureKind.notFound => l10n.errorNotFound,
        ApiFailureKind.standbyTooEarly => l10n.errorStandbyTooEarly,
        ApiFailureKind.standbyReferenceTimeMissing =>
          l10n.errorStandbyReferenceTimeMissing,
        ApiFailureKind.bookingTimeConflict => l10n.errorBookingTimeConflict,
        ApiFailureKind.alreadyClaimed => l10n.errorAlreadyClaimed,
        ApiFailureKind.invalidStatusTransition =>
          l10n.errorInvalidStatusTransition,
        ApiFailureKind.releaseNotAllowed => l10n.errorReleaseNotAllowed,
        ApiFailureKind.assignmentAlreadyReleased =>
          l10n.errorAssignmentAlreadyReleased,
        ApiFailureKind.bookingNotAssigned => l10n.errorBookingNotAssigned,
        ApiFailureKind.validation => l10n.errorValidation,
        ApiFailureKind.invalidFileType => l10n.errorInvalidFileType,
        ApiFailureKind.fileTooLarge => l10n.errorFileTooLarge,
        ApiFailureKind.settlementNotFound => l10n.errorSettlementNotFound,
        ApiFailureKind.receiptAlreadyApproved =>
          l10n.errorReceiptAlreadyApproved,
        ApiFailureKind.driverNotEligible => l10n.errorDriverNotEligible,
        ApiFailureKind.vehiclePlateAlreadyRegistered =>
          l10n.errorVehiclePlateAlreadyRegistered,
        ApiFailureKind.urgentAlreadyLocked => l10n.errorUrgentAlreadyLocked,
        ApiFailureKind.urgentNotUrgentBooking =>
          l10n.errorUrgentNotUrgentBooking,
        ApiFailureKind.urgentNotBroadcasting =>
          l10n.errorUrgentNotBroadcasting,
        ApiFailureKind.urgentEtaInvalid => l10n.errorUrgentEtaInvalid,
        ApiFailureKind.urgentEtaExceedsPickupWindow =>
          l10n.errorUrgentEtaExceedsPickupWindow,
        ApiFailureKind.urgentNotLockedDriver =>
          l10n.errorUrgentNotLockedDriver,
        ApiFailureKind.urgentNegotiationNotFound =>
          l10n.errorUrgentNegotiationNotFound,
        ApiFailureKind.urgentNotLocked => l10n.errorUrgentNotLocked,
        ApiFailureKind.urgentEtaExpired => l10n.errorUrgentEtaExpired,
        ApiFailureKind.urgentEtaNotFastEnough =>
          l10n.errorUrgentEtaNotFastEnough,
        ApiFailureKind.conflict => l10n.errorConflict,
        ApiFailureKind.unavailable => l10n.errorUnavailable,
        ApiFailureKind.timeout => l10n.errorTimeout,
        ApiFailureKind.invalidResponse => l10n.errorInvalidResponse,
        ApiFailureKind.server => l10n.errorServer,
        ApiFailureKind.configuration => l10n.errorConfiguration,
        ApiFailureKind.unknown => l10n.errorUnknown,
      };
}

extension BookingStatusLocalization on BookingStatus {
  String localizedLabel(AppLocalizations l10n) => switch (code) {
        BookingStatusCode.pending => l10n.statusPending,
        BookingStatusCode.open => l10n.statusOpen,
        BookingStatusCode.confirmed => l10n.statusConfirmed,
        BookingStatusCode.driverAssigned => l10n.statusDriverAssigned,
        BookingStatusCode.onRoute => l10n.statusOnRoute,
        BookingStatusCode.driverArrived => l10n.statusDriverArrived,
        BookingStatusCode.pickedUp => l10n.statusPickedUp,
        BookingStatusCode.settlementPending => l10n.statusSettlementPending,
        BookingStatusCode.completed => l10n.statusCompleted,
        BookingStatusCode.cancelled => l10n.statusCancelled,
        BookingStatusCode.noShow => l10n.statusNoShow,
        BookingStatusCode.unknown => l10n.statusUnknown,
      };
}

extension SettlementStatusLocalization on SettlementStatus {
  String localizedLabel(AppLocalizations l10n) => switch (code) {
        SettlementStatusCode.notDueYet => l10n.settlementStatusNotDueYet,
        SettlementStatusCode.due => l10n.settlementStatusDue,
        SettlementStatusCode.receiptSubmitted =>
          l10n.settlementStatusReceiptSubmitted,
        SettlementStatusCode.overdue => l10n.settlementStatusOverdue,
        SettlementStatusCode.rejected => l10n.settlementStatusRejected,
        SettlementStatusCode.approved => l10n.settlementStatusApproved,
        SettlementStatusCode.waived => l10n.settlementStatusWaived,
        SettlementStatusCode.unknown => l10n.settlementStatusUnknown,
      };
}

extension BookingAcceptOutcomeLocalization on BookingAcceptOutcome {
  String localizedMessage(AppLocalizations l10n) => switch (kind) {
        BookingAcceptOutcomeKind.success => l10n.bookingAccepted,
        BookingAcceptOutcomeKind.unauthorized => l10n.sessionExpiredLoginAgain,
        BookingAcceptOutcomeKind.forbidden =>
          error?.localizedMessage(l10n) ?? l10n.errorForbidden,
        BookingAcceptOutcomeKind.notFound => l10n.bookingNotFoundListRefreshed,
        BookingAcceptOutcomeKind.conflictUpdated =>
          l10n.bookingStatusChangedRefresh,
        BookingAcceptOutcomeKind.stillAssigned =>
          error?.localizedMessage(l10n) ?? l10n.bookingNotYetAcceptedRetry,
        BookingAcceptOutcomeKind.alreadyAccepting =>
          l10n.alreadyAcceptingBooking,
        BookingAcceptOutcomeKind.uncertain => l10n.acceptResultUncertainRefresh,
        BookingAcceptOutcomeKind.serverError =>
          error?.localizedMessage(l10n) ?? l10n.errorUnknown,
      };
}

String settlementUploadErrorMessage(
  AppLocalizations l10n,
  ApiException error,
) {
  return switch (error.errorCode) {
    'VALIDATION_ERROR' => l10n.settlementUploadValidationError,
    'INVALID_FILE_TYPE' => l10n.settlementUploadInvalidFileType,
    'FILE_TOO_LARGE' => l10n.settlementUploadFileTooLarge,
    'SETTLEMENT_NOT_FOUND' => l10n.settlementUploadNotFound,
    'RECEIPT_ALREADY_APPROVED' => l10n.settlementUploadAlreadyApproved,
    _ => switch (error.kind) {
        ApiFailureKind.invalidFileType =>
          l10n.settlementUploadInvalidFileType,
        ApiFailureKind.fileTooLarge => l10n.settlementUploadFileTooLarge,
        ApiFailureKind.notFound => l10n.settlementUploadNotFound,
        ApiFailureKind.unauthorized => l10n.errorUnauthorized,
        _ => error.localizedMessage(l10n),
      },
  };
}

String releaseAssignmentErrorMessage(
  AppLocalizations l10n,
  String? errorCode,
) {
  return switch (errorCode) {
    'TRIP_ALREADY_STARTED' => l10n.releaseErrorTripAlreadyStarted,
    'NO_ACTIVE_ASSIGNMENT' => l10n.releaseErrorNoActiveAssignment,
    'NOT_ASSIGNED_DRIVER' => l10n.releaseErrorNotAssignedDriver,
    'BOOKING_TERMINAL_STATUS' => l10n.releaseErrorBookingTerminalStatus,
    'INVALID_PICKUP_TIME' => l10n.releaseErrorInvalidPickupTime,
    'WITHIN_TWO_HOURS' => l10n.releaseErrorWithinTwoHours,
    _ => l10n.releaseErrorGeneric,
  };
}

String nameSignUploadErrorMessage(
  AppLocalizations l10n,
  String? errorCode,
) {
  return switch (errorCode) {
    'VALIDATION_ERROR' => l10n.nameSignValidationError,
    'INVALID_FILE_TYPE' => l10n.nameSignInvalidFileType,
    'FILE_TOO_LARGE' => l10n.nameSignFileTooLarge,
    'BOOKING_NOT_FOUND' => l10n.nameSignBookingNotFound,
    'FORBIDDEN' => l10n.nameSignForbidden,
    _ => l10n.nameSignForbidden,
  };
}

String releaseReasonLabel(AppLocalizations l10n, String reasonCode) {
  return switch (reasonCode) {
    'VEHICLE_BREAKDOWN' => l10n.releaseReasonVehicleBreakdown,
    'ACCIDENT' => l10n.releaseReasonAccident,
    'DRIVER_ILLNESS' => l10n.releaseReasonDriverIllness,
    'FAMILY_EMERGENCY' => l10n.releaseReasonFamilyEmergency,
    'SCHEDULE_CONFLICT' => l10n.releaseReasonScheduleConflict,
    'LOCATION_TOO_FAR' => l10n.releaseReasonLocationTooFar,
    'OTHER' => l10n.releaseReasonOther,
    _ => reasonCode,
  };
}

String vehicleApprovalStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'PENDING' => l10n.approvalPending,
    'REJECTED' => l10n.approvalRejected,
    _ => l10n.approvalComplete,
  };
}

String releaseAssignmentBlockedMessage(
  AppLocalizations l10n,
  String reason,
) =>
    releaseAssignmentErrorMessage(l10n, reason);
