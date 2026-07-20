import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/booking_models.dart';
import '../data/booking_repository.dart';
import 'booking_accept_controller.dart';
import 'booking_status_label.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.bookingNumber,
    required this.repository,
    required this.onUnauthorized,
    this.onAccepted,
    this.acceptController,
  });

  final String bookingNumber;
  final BookingReader repository;
  final Future<void> Function() onUnauthorized;
  final VoidCallback? onAccepted;
  final BookingAcceptController? acceptController;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late final BookingAcceptController _acceptController;
  BookingDetail? _detail;
  ApiException? _error;
  bool _loading = true;
  bool _accepting = false;
  bool _listRefreshRequested = false;

  @override
  void initState() {
    super.initState();
    _acceptController =
        widget.acceptController ?? BookingAcceptController(widget.repository);
    _load();
  }

  @override
  void didUpdateWidget(covariant BookingDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingNumber != widget.bookingNumber ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.getBookingDetail(
        widget.bookingNumber,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _detail = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _detail = null;
        _loading = false;
      });
    }
  }

  Future<void> _confirmAccept() async {
    final detail = _detail;
    if (detail == null || !detail.canAccept || _accepting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_accepting,
      builder: (dialogContext) => AlertDialog(
        key: const Key('acceptConfirmDialog'),
        title: const Text('예약 수락'),
        content: const Text('이 예약을 수락하시겠습니까?'),
        actions: [
          TextButton(
            key: const Key('acceptCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('acceptConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('예약 수락'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runAccept(detail);
  }

  Future<void> _runAccept(BookingDetail detail) async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final outcome = await _acceptController.accept(
      bookingNumber: widget.bookingNumber,
      currentDetail: detail,
    );

    if (!mounted) return;

    if (outcome.refreshList) {
      _listRefreshRequested = true;
      widget.onAccepted?.call();
    }

    if (outcome.expireAuth) {
      await widget.onUnauthorized();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (outcome.closeDetail) {
      _showMessage(outcome.message);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    setState(() {
      _accepting = false;
      if (outcome.detail != null) {
        _detail = outcome.detail;
        _error = null;
        _loading = false;
      }
    });

    _showMessage(outcome.message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _popWithRefreshFlag() {
    Navigator.of(context).pop(_listRefreshRequested);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithRefreshFlag();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('예약 상세'),
          leading: BackButton(onPressed: _popWithRefreshFlag),
        ),
        body: switch ((_loading, _detail, _error)) {
          (true, _, _) => const Center(
            key: Key('detailLoading'),
            child: CircularProgressIndicator(),
          ),
          (false, _, final error?) => _DetailError(
            error: error,
            onRetry: _load,
          ),
          (false, final detail?, _) => _DetailBody(
            detail: detail,
            accepting: _accepting,
            onAcceptPressed: _confirmAccept,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final unavailable =
        error.kind == ApiFailureKind.notFound ||
        error.errorCode == 'BOOKING_NOT_FOUND';
    return Center(
      key: const Key('detailError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unavailable
                  ? Icons.event_busy_outlined
                  : Icons.cloud_off_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              unavailable
                  ? '이 예약은 더 이상 배정 내역에서 확인할 수 없습니다.'
                  : error.userMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (unavailable)
              OutlinedButton(
                key: const Key('detailBackButton'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('목록으로 돌아가기'),
              )
            else
              FilledButton(
                key: const Key('detailRetryButton'),
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.accepting,
    required this.onAcceptPressed,
  });

  final BookingDetail detail;
  final bool accepting;
  final VoidCallback onAcceptPressed;

  @override
  Widget build(BuildContext context) {
    final booking = detail.summary;
    final vehicle = booking.vehicleType.name.isNotEmpty
        ? booking.vehicleType.name
        : booking.vehicleType.code;
    final flight = detail.flight;
    return ListView(
      key: const Key('detailSuccess'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                booking.bookingNumber,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            BookingStatusLabel(status: booking.status),
          ],
        ),
        if (detail.canAccept) ...[
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('acceptBookingButton'),
            onPressed: accepting ? null : onAcceptPressed,
            child: accepting
                ? const SizedBox(
                    key: Key('acceptBookingLoading'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('예약 수락'),
          ),
        ],
        const SizedBox(height: 16),
        _Section(
          title: '운행 정보',
          children: [
            _Info(
              label: '픽업',
              value: '${booking.pickupDate} ${booking.pickupTime}',
            ),
            _Info(label: '출발지', value: booking.origin),
            _Info(label: '목적지', value: booking.destination),
          ],
        ),
        _Section(
          title: '고객 및 탑승 정보',
          children: [
            _Info(label: '고객명', value: booking.customerDisplayName),
            _Info(
              label: '총 인원',
              value: booking.passengerCount == null
                  ? null
                  : '${booking.passengerCount}명',
            ),
            _Info(label: '구성', value: detail.passengers.display),
            _Info(label: '수하물', value: detail.luggage.display),
          ],
        ),
        _Section(
          title: '항공편 및 차량',
          children: [
            _Info(
              label: '항공편',
              value: flight.flightNumber ?? booking.flightNumber,
            ),
            _Info(label: '항공편 상태', value: flight.flightStatus),
            _Info(label: '도착 예정', value: flight.latestEstimatedArrival),
            _Info(
              label: '지연',
              value: flight.delayMinutes == null
                  ? null
                  : '${flight.delayMinutes}분',
            ),
            _Info(label: '차량', value: vehicle.isEmpty ? null : vehicle),
          ],
        ),
        _Section(
          title: '금액 정보',
          children: [
            _Info(
              label: '고객 결제 금액',
              value: formatMoney(detail.customerPayment),
            ),
            _Info(
              label: '회사 수수료',
              value: formatMoney(detail.companyCommission),
            ),
            _Info(
              label: '기사 예상 수입',
              value: formatMoney(booking.driverExpectedIncome),
            ),
          ],
        ),
        if (detail.specialInstructions case final instructions?)
          _Section(
            title: '기사 참고 사항',
            children: [_Info(label: '고객 요청', value: instructions)],
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
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final display = value?.trim();
    if (display == null || display.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label)),
          Expanded(child: Text(display)),
        ],
      ),
    );
  }
}
