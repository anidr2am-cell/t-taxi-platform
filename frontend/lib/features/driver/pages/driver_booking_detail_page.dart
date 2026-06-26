import 'package:flutter/material.dart';

import '../models/driver_booking.dart';
import '../services/driver_api_service.dart';

class DriverBookingDetailPage extends StatefulWidget {
  const DriverBookingDetailPage({super.key, required this.bookingNumber});

  final String bookingNumber;

  @override
  State<DriverBookingDetailPage> createState() => _DriverBookingDetailPageState();
}

class _DriverBookingDetailPageState extends State<DriverBookingDetailPage> {
  final _api = DriverApiService();
  late Future<DriverBooking> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getBookingDetail(widget.bookingNumber);
  }

  void _refresh() {
    setState(() {
      _future = _api.getBookingDetail(widget.bookingNumber);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookingNumber),
        actions: [
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
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
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
                  _Line(label: 'Pickup', value: '${booking.pickupDate} ${booking.pickupTime}'),
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
                  _Line(label: 'Passengers', value: booking.passengerCount.toString()),
                  _Line(label: 'Vehicle', value: booking.vehicleTypeName),
                  if (booking.luggage != null)
                    _Line(label: 'Luggage', value: _formatLuggage(booking.luggage!)),
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
                      _Line(label: 'Estimated arrival', value: booking.latestEstimatedArrival!),
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
                title: 'Allowed actions',
                children: [
                  Text(
                    booking.allowedActions.isEmpty
                        ? 'No actions available'
                        : booking.allowedActions.join(', '),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatLuggage(Map<String, dynamic> luggage) {
    return [
      '20": ${luggage['carriers20Inch'] ?? 0}',
      '24"+: ${luggage['carriers24InchPlus'] ?? 0}',
      'Golf: ${luggage['golfBags'] ?? 0}',
    ].join(' · ');
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
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
