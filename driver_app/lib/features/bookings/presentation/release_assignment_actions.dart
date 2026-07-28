import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/booking_repository.dart';
import 'release_assignment_dialog.dart';

Future<bool> confirmReleaseAssignment({
  required BuildContext context,
  required BookingReader repository,
  required String bookingNumber,
  required bool emergencyOnly,
}) async {
  final input = await showDialog<ReleaseAssignmentInput>(
    context: context,
    builder: (_) => ReleaseAssignmentDialog(emergencyOnly: emergencyOnly),
  );
  if (input == null) return false;

  await repository.releaseAssignment(
    bookingNumber,
    reasonCode: input.reasonCode,
    reasonDetail: input.reasonDetail,
  );
  return true;
}

Future<void> handleReleaseAssignmentError({
  required BuildContext context,
  required ApiException error,
  required Future<void> Function() onUnauthorized,
  required Future<void> Function() onReload,
  required void Function(String message) showMessage,
}) async {
  if (error.kind == ApiFailureKind.unauthorized) {
    await onUnauthorized();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    return;
  }

  final l10n = AppLocalizations.of(context);
  showMessage(error.localizedMessage(l10n));
  if (error.kind == ApiFailureKind.invalidStatusTransition ||
      error.kind == ApiFailureKind.bookingNotAssigned ||
      error.kind == ApiFailureKind.assignmentAlreadyReleased) {
    await onReload();
  }
}
