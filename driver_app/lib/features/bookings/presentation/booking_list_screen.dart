import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../dispatch/data/driver_socket_service.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import 'booking_detail_screen.dart';
import 'booking_list_item.dart';
import 'release_assignment_actions.dart';
import 'release_assignment_ui.dart';

class BookingListScreen extends StatefulWidget {
  const BookingListScreen({
    super.key,
    required this.repository,
    required this.onUnauthorized,
    this.socketEvents,
    this.refreshRequest = 0,
    this.now,
  });

  final BookingReader repository;
  final Future<void> Function() onUnauthorized;
  final Stream<DriverSocketEvent>? socketEvents;
  final int refreshRequest;
  final DateTime Function()? now;

  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  BookingList? _bookings;
  ApiException? _error;
  bool _loading = true;
  int _loadGeneration = 0;
  final Map<String, BookingCapabilities> _releaseCapabilitiesByBooking = {};
  String? _releasingBookingNumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookingListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRequest != widget.refreshRequest) {
      _load();
    }
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await widget.repository.getTodayBookings();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
        _releaseCapabilitiesByBooking.clear();
      });
      await _prefetchReleaseCapabilities(bookings, generation);
    } on ApiException catch (error) {
      if (generation != _loadGeneration) return;
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _bookings = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _bookings = null;
        _loading = false;
      });
    }
  }

  Future<void> _prefetchReleaseCapabilities(
    BookingList bookings,
    int generation,
  ) async {
    final eligible = bookings.items
        .where((booking) => booking.allowsAction('RELEASE_ASSIGNMENT'))
        .toList(growable: false);
    if (eligible.isEmpty) return;

    final results = await Future.wait(
      eligible.map((booking) async {
        try {
          final detail = await widget.repository.getBookingDetail(
            booking.bookingNumber,
          );
          return MapEntry(booking.bookingNumber, detail.capabilities);
        } catch (_) {
          return null;
        }
      }),
    );

    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      for (final entry in results) {
        if (entry != null) {
          _releaseCapabilitiesByBooking[entry.key] = entry.value;
        }
      }
    });
  }

  Future<void> _confirmReleaseFromList(BookingSummary booking) async {
    final capabilities = _releaseCapabilitiesByBooking[booking.bookingNumber];
    if (capabilities == null || _releasingBookingNumber != null) return;

    final releaseUi = ReleaseAssignmentUiState.evaluate(
      booking: booking,
      capabilities: capabilities,
      now: _now,
    );
    if (!releaseUi.releaseEnabled) return;

    setState(() => _releasingBookingNumber = booking.bookingNumber);
    try {
      final released = await confirmReleaseAssignment(
        context: context,
        repository: widget.repository,
        bookingNumber: booking.bookingNumber,
        emergencyOnly: releaseUi.emergencyOnly,
      );
      if (!mounted) return;
      if (!released) {
        setState(() => _releasingBookingNumber = null);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('배정을 반납했습니다.')));
      setState(() => _releasingBookingNumber = null);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _releasingBookingNumber = null);
      await handleReleaseAssignmentError(
        context: context,
        error: error,
        onUnauthorized: widget.onUnauthorized,
        onReload: _load,
        showMessage: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _releasingBookingNumber = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(const ApiException(ApiFailureKind.unknown).userMessage),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘의 배정 예약'),
        actions: [
          IconButton(
            key: const Key('refreshButton'),
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch ((_loading, _bookings, _error)) {
        (true, _, _) => const Center(
          key: Key('bookingListLoading'),
          child: CircularProgressIndicator(),
        ),
        (false, _, final error?) => Center(
          key: const Key('bookingListError'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 12),
                Text(error.userMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('bookingListRetryButton'),
                  onPressed: _load,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        (false, final bookings?, _) when bookings.items.isEmpty =>
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              key: const Key('bookingListEmpty'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Icon(Icons.event_available_outlined, size: 56),
                SizedBox(height: 12),
                Center(child: Text('오늘 배정된 예약이 없습니다.')),
              ],
            ),
          ),
        (false, final bookings?, _) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            key: const Key('bookingListSuccess'),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: bookings.items.length,
            itemBuilder: (context, index) {
              final booking = bookings.items[index];
              return BookingListItem(
                booking: booking,
                capabilities:
                    _releaseCapabilitiesByBooking[booking.bookingNumber],
                now: _now,
                releaseBusy: _releasingBookingNumber == booking.bookingNumber,
                onReleasePressed: () => _confirmReleaseFromList(booking),
                onTap: () async {
                  final shouldRefresh = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => BookingDetailScreen(
                        bookingNumber: booking.bookingNumber,
                        repository: widget.repository,
                        onUnauthorized: widget.onUnauthorized,
                        socketEvents: widget.socketEvents,
                        now: widget.now,
                      ),
                    ),
                  );
                  if (shouldRefresh == true && mounted) {
                    await _load();
                  }
                },
              );
            },
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
