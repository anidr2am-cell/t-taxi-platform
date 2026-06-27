import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/driver_booking.dart';
import '../pages/driver_chat_page.dart';
import '../services/driver_api_service.dart';

class DriverBookingDetailPage extends StatefulWidget {
  const DriverBookingDetailPage({
    super.key,
    required this.bookingNumber,
    DriverApiService? api,
  }) : api = api ?? const DriverApiService();

  final String bookingNumber;
  final DriverApiService api;

  @override
  State<DriverBookingDetailPage> createState() =>
      _DriverBookingDetailPageState();
}

class _DriverBookingDetailPageState extends State<DriverBookingDetailPage> {
  late Future<DriverBooking> _future;
  bool _processing = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getBookingDetail(widget.bookingNumber);
  }

  void _refresh() {
    setState(() {
      _actionError = null;
      _future = widget.api.getBookingDetail(widget.bookingNumber);
    });
  }

  Future<void> _runAction(
    Future<DriverBooking> Function() action,
    String message,
  ) async {
    setState(() {
      _processing = true;
      _actionError = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
        _processing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _actionError = err.toString();
      });
    }
  }

  Future<void> _manualTokenAction({
    required String title,
    required Future<DriverBooking> Function(String token) action,
    required String successMessage,
  }) async {
    final token = await showDialog<String>(
      context: context,
      builder: (context) => _QrTokenDialog(title: title),
    );
    if (token == null || token.trim().isEmpty) return;
    await _runAction(() => action(token.trim()), successMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookingNumber),
        actions: [
          IconButton(
            tooltip: 'Open chat',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverChatPage(bookingNumber: widget.bookingNumber),
                ),
              );
            },
            icon: const Icon(Icons.chat),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<DriverBooking>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load booking'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final booking = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: 'Route',
                children: [
                  _Line(
                    label: 'Pickup',
                    value: '${booking.pickupDate} ${booking.pickupTime}',
                  ),
                  _Line(label: 'From', value: booking.origin),
                  _Line(label: 'To', value: booking.destination),
                  _Line(label: 'Status', value: booking.status),
                ],
              ),
              _Section(
                title: 'Customer',
                children: [
                  if (booking.customerDisplayName != null)
                    _Line(label: 'Name', value: booking.customerDisplayName!),
                  if (booking.customerPhone != null)
                    _Line(label: 'Phone', value: booking.customerPhone!),
                ],
              ),
              _Section(
                title: 'Passengers and luggage',
                children: [
                  _Line(
                    label: 'Passengers',
                    value: booking.passengerCount.toString(),
                  ),
                  _Line(label: 'Vehicle', value: booking.vehicleTypeName),
                  if (booking.luggage != null)
                    _Line(
                      label: 'Luggage',
                      value: _formatLuggage(booking.luggage!),
                    ),
                ],
              ),
              if (booking.flightNumber != null)
                _Section(
                  title: 'Flight',
                  children: [
                    _Line(label: 'Flight', value: booking.flightNumber!),
                    if (booking.flightStatus != null)
                      _Line(label: 'Status', value: booking.flightStatus!),
                    if (booking.latestEstimatedArrival != null)
                      _Line(
                        label: 'Estimated arrival',
                        value: booking.latestEstimatedArrival!,
                      ),
                  ],
                ),
              _Section(
                title: 'Instructions',
                children: [
                  _Line(
                    label: 'Special',
                    value: booking.specialInstructions?.isNotEmpty == true
                        ? booking.specialInstructions!
                        : 'None',
                  ),
                  if (booking.paymentMethod != null)
                    _Line(label: 'Payment', value: booking.paymentMethod!),
                ],
              ),
              _Section(
                title: 'Actions',
                children: [
                  if (_processing) const LinearProgressIndicator(),
                  if (_actionError != null) ...[
                    Text(
                      _actionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ..._buildActionButtons(booking),
                  if (booking.allowedActions.isEmpty &&
                      booking.status == 'COMPLETED')
                    const Text('Trip completed'),
                  if (booking.allowedActions.isEmpty &&
                      booking.status != 'COMPLETED')
                    const Text('No actions available'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildActionButtons(DriverBooking booking) {
    final actions = booking.allowedActions;
    return [
      if (actions.contains('MARK_ARRIVED'))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ElevatedButton.icon(
            onPressed: _processing
                ? null
                : () => _runAction(
                    () => widget.api.markArrived(widget.bookingNumber),
                    'Arrival marked',
                  ),
            icon: const Icon(Icons.place),
            label: const Text('Mark arrived'),
          ),
        ),
      if (actions.contains('SCAN_BOARDING_QR'))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ElevatedButton.icon(
            onPressed: _processing
                ? null
                : () => _manualTokenAction(
                    title: 'Boarding QR token',
                    action: (token) =>
                        widget.api.scanBoarding(widget.bookingNumber, token),
                    successMessage: 'Pickup completed',
                  ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan boarding QR'),
          ),
        ),
      if (actions.contains('SCAN_DROPOFF_QR'))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ElevatedButton.icon(
            onPressed: _processing
                ? null
                : () => _manualTokenAction(
                    title: 'Dropoff QR token',
                    action: (token) =>
                        widget.api.scanDropoff(widget.bookingNumber, token),
                    successMessage: 'Trip completed',
                  ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan dropoff QR'),
          ),
        ),
    ];
  }

  String _formatLuggage(Map<String, dynamic> luggage) {
    return [
      '20": ${luggage['carriers20Inch'] ?? 0}',
      '24"+: ${luggage['carriers24InchPlus'] ?? 0}',
      'Golf: ${luggage['golfBags'] ?? 0}',
    ].join(' · ');
  }
}

class _QrTokenDialog extends StatefulWidget {
  const _QrTokenDialog({required this.title});

  final String title;

  @override
  State<_QrTokenDialog> createState() => _QrTokenDialogState();
}

class _QrTokenDialogState extends State<_QrTokenDialog> {
  final _controller = TextEditingController();
  bool _cameraMode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: _cameraMode
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 240,
                    child: MobileScanner(
                      onDetect: (capture) {
                        String? value;
                        for (final barcode in capture.barcodes) {
                          if (barcode.rawValue?.isNotEmpty == true) {
                            value = barcode.rawValue;
                            break;
                          }
                        }
                        if (value != null && value.trim().isNotEmpty) {
                          Navigator.of(context).pop(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Use manual entry if camera is unavailable.'),
                ],
              )
            : TextField(
                key: const Key('manualQrTokenField'),
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'QR token'),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _cameraMode = !_cameraMode),
          child: Text(_cameraMode ? 'Manual entry' : 'Use camera'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
