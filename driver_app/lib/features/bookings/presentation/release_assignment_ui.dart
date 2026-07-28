import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/booking_models.dart';

class ReleaseAssignmentUiState {
  const ReleaseAssignmentUiState({
    required this.releaseActionAllowed,
    required this.releaseEnabled,
    required this.releaseRelevant,
    required this.emergencyOnly,
    required this.deadlinePassed,
    required this.blockedReason,
  });

  final bool releaseActionAllowed;
  final bool releaseEnabled;
  final bool releaseRelevant;
  final bool emergencyOnly;
  final bool deadlinePassed;
  final String? blockedReason;

  static ReleaseAssignmentUiState evaluate({
    required BookingSummary booking,
    required BookingCapabilities capabilities,
    required DateTime now,
  }) {
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

    return ReleaseAssignmentUiState(
      releaseActionAllowed: releaseActionAllowed,
      releaseEnabled: releaseEnabled,
      releaseRelevant: releaseRelevant,
      emergencyOnly: emergencyOnly,
      deadlinePassed: deadlinePassed,
      blockedReason: capabilities.assignmentReleaseBlockedReason,
    );
  }
}

class ReleaseAssignmentDetailSection extends StatelessWidget {
  const ReleaseAssignmentDetailSection({
    super.key,
    required this.uiState,
    required this.performingAction,
    required this.onReleasePressed,
    this.prominent = false,
    this.compact = false,
  });

  final ReleaseAssignmentUiState uiState;
  final bool performingAction;
  final VoidCallback onReleasePressed;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!uiState.releaseRelevant) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final button = compact
        ? IconButton(
            key: const Key('releaseAssignmentButton'),
            tooltip: l10n.releaseAssignmentTooltip,
            onPressed: uiState.releaseEnabled && !performingAction
                ? onReleasePressed
                : null,
            icon: const Icon(Icons.assignment_return_outlined),
          )
        : OutlinedButton.icon(
            key: const Key('releaseAssignmentButton'),
            onPressed: uiState.releaseEnabled && !performingAction
                ? onReleasePressed
                : null,
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(l10n.releaseAssignment),
          );

    final notices = <Widget>[
      if (uiState.emergencyOnly)
        Text(
          l10n.releasePastDeadlineEmergencyOnly,
          key: const Key('releaseEmergencyOnlyNotice'),
          textAlign: TextAlign.center,
        )
      else if (uiState.blockedReason case final reason?)
        Text(
          releaseAssignmentBlockedMessage(l10n, reason),
          key: const Key('releaseBlockedNotice'),
          textAlign: TextAlign.center,
        )
      else if (uiState.deadlinePassed)
        Text(
          l10n.releaseDeadlinePassed,
          key: const Key('releaseDeadlineNotice'),
          textAlign: TextAlign.center,
        ),
    ];

    if (!prominent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          for (final notice in notices) ...[const SizedBox(height: 8), notice],
        ],
      );
    }

    final theme = Theme.of(context);
    return Card(
      key: const Key('releaseAssignmentProminentCard'),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.releaseAssignmentTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.releaseBeforeAcceptHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            button,
            for (final notice in notices) ...[const SizedBox(height: 8), notice],
          ],
        ),
      ),
    );
  }
}

class PreAcceptReleaseActionCard extends StatelessWidget {
  const PreAcceptReleaseActionCard({
    super.key,
    required this.uiState,
    required this.accepting,
    required this.performingAction,
    required this.onAcceptPressed,
    required this.onReleasePressed,
  });

  final ReleaseAssignmentUiState uiState;
  final bool accepting;
  final bool performingAction;
  final VoidCallback onAcceptPressed;
  final VoidCallback onReleasePressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('preAcceptReleaseActionCard'),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.assignmentHandlingTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.acceptOrReleaseHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('releaseAssignmentButton'),
                    onPressed: uiState.releaseEnabled && !performingAction
                        ? onReleasePressed
                        : null,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(l10n.releaseAssignment),
                  ),
                ),
              ],
            ),
            if (uiState.emergencyOnly) ...[
              const SizedBox(height: 8),
              Text(
                l10n.releasePastDeadlineEmergencyOnly,
                key: const Key('releaseEmergencyOnlyNotice'),
                textAlign: TextAlign.center,
              ),
            ] else if (uiState.blockedReason case final reason?) ...[
              const SizedBox(height: 8),
              Text(
                releaseAssignmentBlockedMessage(l10n, reason),
                key: const Key('releaseBlockedNotice'),
                textAlign: TextAlign.center,
              ),
            ] else if (uiState.deadlinePassed) ...[
              const SizedBox(height: 8),
              Text(
                l10n.releaseDeadlinePassed,
                key: const Key('releaseDeadlineNotice'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReleaseAssignmentListButton extends StatelessWidget {
  const ReleaseAssignmentListButton({
    super.key,
    required this.bookingNumber,
    required this.uiState,
    required this.busy,
    required this.onPressed,
  });

  final String bookingNumber;
  final ReleaseAssignmentUiState uiState;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!uiState.releaseRelevant) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: Key('releaseAssignmentListButton-$bookingNumber'),
      tooltip: l10n.releaseAssignmentTooltip,
      onPressed: uiState.releaseEnabled && !busy ? onPressed : null,
      icon: busy
          ? const SizedBox(
              key: Key('releaseAssignmentListLoading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.assignment_return_outlined),
    );
  }
}
