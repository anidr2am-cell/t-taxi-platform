import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import 'booking_detail_screen.dart';
import 'booking_list_item.dart';

class BookingListScreen extends StatefulWidget {
  const BookingListScreen({
    super.key,
    required this.repository,
    required this.onUnauthorized,
    required this.onLogout,
  });

  final BookingReader repository;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;

  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  BookingList? _bookings;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await widget.repository.getTodayBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _loading = false;
      });
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
          TextButton(
            key: const Key('logoutButton'),
            onPressed: widget.onLogout,
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: switch ((_loading, _bookings, _error)) {
        (true, _, _) => const Center(
          key: Key('bookingListLoading'),
          child: CircularProgressIndicator(),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BookingDetailScreen(
                      bookingNumber: booking.bookingNumber,
                      repository: widget.repository,
                      onUnauthorized: widget.onUnauthorized,
                    ),
                  ),
                ),
              );
            },
          ),
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
        _ => const SizedBox.shrink(),
      },
    );
  }
}
