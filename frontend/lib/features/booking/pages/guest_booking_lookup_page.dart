import 'package:flutter/material.dart';

import '../models/guest_booking_lookup_result.dart';
import '../services/booking_api_service.dart';
import '../services/booking_chat_api.dart';
import '../services/guest_booking_lookup_service.dart';
import '../widgets/booking_chat_section.dart';
import '../widgets/booking_notification_section.dart';
import '../widgets/booking_review_form.dart';

class GuestBookingLookupPage extends StatefulWidget {
  const GuestBookingLookupPage({
    super.key,
    this.lookupService,
    this.bookingApiService,
    this.enableCustomerTools = true,
  });

  final GuestBookingLookupService? lookupService;
  final BookingApiService? bookingApiService;
  final bool enableCustomerTools;

  @override
  State<GuestBookingLookupPage> createState() => _GuestBookingLookupPageState();
}

class _GuestBookingLookupPageState extends State<GuestBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  late final GuestBookingLookupService _lookupService =
      widget.lookupService ?? GuestBookingLookupService();
  late final BookingApiService _bookingApiService =
      widget.bookingApiService ?? BookingApiService();

  GuestBookingLookupResult? _result;
  bool _loading = true;
  String? _error;
  bool _loadingDropoffQr = false;
  String? _dropoffQrToken;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  @override
  void dispose() {
    _bookingNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final cached = await _lookupService.loadCached();
    if (!mounted) return;
    setState(() {
      _result = cached;
      _loading = false;
    });
  }

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _dropoffQrToken = null;
    });

    try {
      final result = await _lookupService.lookup(
        bookingNumber: _bookingNumberController.text,
        phone: _phoneController.text,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.errorCode == 'BOOKING_NOT_FOUND'
            ? 'Booking not found. Please check your booking number and phone.'
            : err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load booking. Please try again.';
      });
    }
  }

  Future<void> _clear() async {
    await _lookupService.clearCached();
    if (!mounted) return;
    setState(() {
      _result = null;
      _error = null;
      _dropoffQrToken = null;
      _bookingNumberController.clear();
      _phoneController.clear();
    });
  }

  Future<void> _issueDropoffQr() async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _loadingDropoffQr = true;
      _error = null;
    });
    try {
      final qr = await _bookingApiService.issueDropoffQr(
        bookingNumber: result.bookingNumber,
        guestAccessToken: result.guestAccessToken,
      );
      if (!mounted) return;
      setState(() {
        _dropoffQrToken = qr.dropoffQrToken;
        _loadingDropoffQr = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingDropoffQr = false;
        _error = err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Find my booking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _result == null ? _lookupForm() : _bookingDetail(_result!),
          ),
        ),
      ),
    );
  }

  Widget _lookupForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('guest_lookup_booking_number'),
            controller: _bookingNumberController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Booking number',
              hintText: 'TX202607010001',
            ),
            validator: (value) {
              final normalized = (value ?? '').trim().toUpperCase();
              return RegExp(r'^TX\d{12}$').hasMatch(normalized)
                  ? null
                  : 'Enter a valid booking number';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('guest_lookup_phone'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.length >= 4 ? null : 'Enter the booking phone number';
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _lookup,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Find booking'),
          ),
        ],
      ),
    );
  }

  Widget _bookingDetail(GuestBookingLookupResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.bookingNumber, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _row('Status', result.status),
                _row('Pickup', result.scheduledPickupAt ?? '-'),
                _row('Service', result.serviceTypeName),
                _row('From', result.originAddress),
                _row('To', result.destinationAddress),
                _row('Total', '${result.totalAmount} ${result.currency}'),
                _row('Payment', result.paymentMethod),
                if (result.driverName != null) ...[
                  const Divider(),
                  _row('Driver', result.driverName!),
                  if (result.driverPhone != null) _row('Driver phone', result.driverPhone!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _qrSection(result),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (widget.enableCustomerTools) ...[
          const SizedBox(height: 16),
          if (result.capabilities.notificationsAvailable)
            BookingNotificationSection(
              bookingNumber: result.bookingNumber,
              bookingId: result.bookingId,
              guestAccessToken: result.guestAccessToken,
            ),
          if (result.capabilities.chatAvailable) ...[
            const SizedBox(height: 16),
            BookingChatSection(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
              api: const BookingChatApi(),
            ),
          ],
          if (result.capabilities.reviewAvailable) ...[
            const SizedBox(height: 16),
            BookingReviewForm(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
            ),
          ],
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _clear,
          child: const Text('Look up another booking'),
        ),
      ],
    );
  }

  Widget _qrSection(GuestBookingLookupResult result) {
    if (result.status == 'COMPLETED') {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Trip completed. Active QR codes are hidden.'),
        ),
      );
    }

    if (_dropoffQrToken != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('Dropoff QR token: $_dropoffQrToken'),
        ),
      );
    }

    if (result.capabilities.dropoffQrIssueAvailable) {
      return ElevatedButton.icon(
        onPressed: _loadingDropoffQr ? null : _issueDropoffQr,
        icon: _loadingDropoffQr
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.qr_code),
        label: const Text('Issue dropoff QR'),
      );
    }

    if (result.capabilities.boardingQrPreviouslyIssued) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Boarding QR was issued when the booking was created. '
            'For security, it cannot be recovered from lookup.',
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
