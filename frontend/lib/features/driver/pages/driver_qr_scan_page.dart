// Legacy QR scan screen — kept for compatibility; driver shell no longer navigates here.
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../services/driver_api_service.dart';
import '../widgets/driver_qr_scan_sheet.dart';
import 'driver_booking_detail_page.dart';

typedef DriverQrScannerLauncher =
    Future<bool?> Function(
      BuildContext context,
      bool isBoarding,
      Future<void> Function(String token) onSubmit,
    );

class DriverQrScanPage extends StatefulWidget {
  const DriverQrScanPage({super.key, required this.api, this.scannerLauncher});

  final DriverApiService api;
  final DriverQrScannerLauncher? scannerLauncher;

  @override
  State<DriverQrScanPage> createState() => _DriverQrScanPageState();
}

class _DriverQrScanPageState extends State<DriverQrScanPage> {
  late Future<DriverBooking?> _activeBookingFuture = _loadActiveBooking();
  bool _openingScanner = false;

  Future<DriverBooking?> _loadActiveBooking() async {
    final today = await widget.api.getTodayBookings();
    for (final booking in today.items) {
      if (DriverUx.groupForStatus(booking.status) == DriverJobGroup.active) {
        return booking;
      }
    }
    return null;
  }

  void _refresh() {
    setState(() => _activeBookingFuture = _loadActiveBooking());
  }

  Future<void> _scan(DriverBooking booking) async {
    if (_openingScanner) return;
    final isBoarding = booking.status != 'PICKED_UP';
    setState(() => _openingScanner = true);

    final launcher =
        widget.scannerLauncher ??
        (context, boarding, onSubmit) => showDriverQrScanSheet(
          context: context,
          isBoarding: boarding,
          onSubmit: onSubmit,
          initialCameraMode: true,
        );

    final result = await launcher(context, isBoarding, (token) async {
      try {
        if (isBoarding) {
          await widget.api.scanBoarding(booking.bookingNumber, token);
        } else {
          await widget.api.scanDropoff(booking.bookingNumber, token);
        }
      } on DriverApiException catch (error) {
        if (!mounted) rethrow;
        if (driverIsAuthError(error)) {
          driverHandleApiError(context, error);
        }
        throw _DriverQrUserError(context.l10n.t('driver_qr_scan_invalid'));
      }
    });

    if (!mounted) return;
    setState(() => _openingScanner = false);
    if (result != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(
            isBoarding
                ? 'driver_qr_scan_success_boarding'
                : 'driver_qr_scan_success_dropoff',
          ),
        ),
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverBookingDetailPage(
          bookingNumber: booking.bookingNumber,
          api: widget.api,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('driver_qr_scan_menu')),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('driver_refresh'),
          ),
        ],
      ),
      body: FutureBuilder<DriverBooking?>(
        future: _activeBookingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AppUi.loadingState();
          }
          if (snapshot.hasError) {
            return AppUi.errorState(
              message: l10n.t('driver_load_failed'),
              onRetry: _refresh,
              retryLabel: l10n.t('driver_retry'),
            );
          }
          final booking = snapshot.data;
          if (booking == null) {
            return AppUi.emptyState(
              title: l10n.t('driver_qr_scan_no_active_job'),
              message: l10n.t('driver_qr_scan_instruction'),
              icon: Icons.qr_code_scanner,
            );
          }

          final isBoarding = booking.status != 'PICKED_UP';
          return ListView(
            padding: AppUi.pagePadding(context),
            children: [
              AppUi.surfaceCard(
                backgroundColor: AppTokens.primaryLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      booking.bookingNumber,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      l10n.t('driver_qr_scan_instruction'),
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.primaryButton(
                      label: l10n.t('driver_qr_scan_menu'),
                      icon: Icons.qr_code_scanner,
                      onPressed: _openingScanner ? null : () => _scan(booking),
                      loading: _openingScanner,
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      l10n.t(
                        isBoarding
                            ? 'driver_qr_boarding_help'
                            : 'driver_qr_dropoff_help',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DriverQrUserError implements Exception {
  const _DriverQrUserError(this.message);

  final String message;
}
