import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/airport_label_resolver.dart';
import '../data/dispatch_models.dart';
import '../data/dispatch_repository.dart';
import '../data/driver_socket_service.dart';
import 'vehicle_select_sheet.dart';

class OpenCallsScreen extends StatefulWidget {
  const OpenCallsScreen({
    super.key,
    required this.repository,
    required this.onUnauthorized,
    required this.onClaimed,
    this.driverSocket,
  });

  final DispatchReader repository;
  final Future<void> Function() onUnauthorized;
  final VoidCallback onClaimed;
  final DriverSocketConnection? driverSocket;

  @override
  State<OpenCallsScreen> createState() => _OpenCallsScreenState();
}

class _OpenCallsScreenState extends State<OpenCallsScreen>
    with WidgetsBindingObserver {
  DriverDispatchStatus? _status;
  OpenCallList? _calls;
  ApiException? _statusError;
  ApiException? _callsError;
  bool _loadingStatus = true;
  bool _loadingCalls = false;
  bool _changingOnline = false;
  final Set<String> _claiming = {};
  StreamSubscription<DriverSocketEvent>? _socketSubscription;
  bool _foreground = true;
  bool _showNewCallNotice = false;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _socketSubscription = widget.driverSocket?.events.listen(
      _handleSocketEvent,
    );
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSubscription?.cancel();
    widget.driverSocket?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground && _status?.online == true) {
      unawaited(_connectSocket());
    } else {
      widget.driverSocket?.disconnect();
    }
  }

  Future<void> _connectSocket() async {
    try {
      await widget.driverSocket?.connect();
    } catch (_) {
      // REST remains the source of truth if the foreground socket is unavailable.
    }
  }

  void _syncSocket(DriverDispatchStatus status) {
    if (status.online && _foreground) {
      unawaited(_connectSocket());
    } else {
      widget.driverSocket?.disconnect();
    }
  }

  void _handleSocketEvent(DriverSocketEvent event) {
    if (!mounted || _status?.online != true || !_foreground) return;
    switch (event.type) {
      case DriverSocketEventType.newCall:
        setState(() => _showNewCallNotice = true);
        unawaited(_loadCalls());
      case DriverSocketEventType.callClaimed:
      case DriverSocketEventType.callConfirmed:
      case DriverSocketEventType.assignmentReleased:
      case DriverSocketEventType.reconnected:
        unawaited(_loadCalls());
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await widget.repository.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
      _syncSocket(status);
      if (status.online) {
        await _loadCalls();
      } else {
        setState(() {
          _calls = null;
          _callsError = null;
        });
      }
    } on ApiException catch (error) {
      await _handleStatusError(error);
    } catch (_) {
      await _handleStatusError(const ApiException(ApiFailureKind.unknown));
    }
  }

  Future<void> _handleStatusError(ApiException error) async {
    if (error.kind == ApiFailureKind.unauthorized) {
      await widget.onUnauthorized();
      return;
    }
    if (!mounted) return;
    setState(() {
      _statusError = error;
      _loadingStatus = false;
    });
    widget.driverSocket?.disconnect();
  }

  Future<void> _loadCalls() async {
    if (_status?.online != true) return;
    setState(() {
      _loadingCalls = true;
      _callsError = null;
    });
    try {
      final calls = await widget.repository.getOpenCalls();
      if (!mounted) return;
      setState(() {
        _calls = OpenCallList(
          items: calls.items
              .where((call) => !call.isUrgentRequest)
              .toList(growable: false),
          blockedReason: calls.blockedReason,
          message: calls.message,
        );
        _loadingCalls = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _callsError = error;
        _loadingCalls = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _callsError = const ApiException(ApiFailureKind.unknown);
        _loadingCalls = false;
      });
    }
  }

  Future<void> _setOnline(bool online) async {
    if (_changingOnline || _status == null) return;
    setState(() => _changingOnline = true);
    try {
      final status = online
          ? await widget.repository.goOnline()
          : await widget.repository.goOffline();
      if (!mounted) return;
      setState(() {
        _status = status;
        _changingOnline = false;
        if (!status.online) {
          _calls = null;
          _callsError = null;
          _showNewCallNotice = false;
        }
      });
      _syncSocket(status);
      if (status.online) await _loadCalls();
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() => _changingOnline = false);
      _showMessage(error.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _changingOnline = false);
      _showMessage(const ApiException(ApiFailureKind.unknown).userMessage);
    }
  }

  Future<void> _selectCall(OpenCall call) async {
    if (_claiming.contains(call.bookingNumber)) return;
    final vehicles = call.compatibleVehicles;
    if (vehicles.isEmpty) {
      _showMessage('이 콜에 사용할 수 있는 승인 차량이 없습니다.');
      return;
    }

    final vehicle = vehicles.length == 1
        ? vehicles.single
        : await showVehicleSelectSheet(context, vehicles);
    if (vehicle == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('claimConfirmDialog'),
        title: const Text('새 콜 받기'),
        content: Text('${vehicle.displayName} 차량으로 이 콜을 받으시겠습니까?'),
        actions: [
          TextButton(
            key: const Key('claimCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('claimConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('콜 받기'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _claim(call, vehicle);
    }
  }

  Future<void> _claim(OpenCall call, CompatibleVehicle vehicle) async {
    setState(() => _claiming.add(call.bookingNumber));
    try {
      await widget.repository.claimOpenCall(
        call.bookingNumber,
        vehicle.driverVehicleId,
      );
      if (!mounted) return;
      setState(() {
        _claiming.remove(call.bookingNumber);
        final current = _calls;
        if (current != null) {
          _calls = OpenCallList(
            items: current.items
                .where((item) => item.bookingNumber != call.bookingNumber)
                .toList(growable: false),
            blockedReason: current.blockedReason,
            message: current.message,
          );
        }
      });
      _showMessage('콜 배정이 완료되었습니다.');
      widget.onClaimed();
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      final alreadyClaimed =
          error.kind == ApiFailureKind.alreadyClaimed ||
          error.errorCode == 'ALREADY_ASSIGNED' ||
          error.errorCode == 'BOOKING_NOT_FOUND';
      setState(() {
        _claiming.remove(call.bookingNumber);
        if (alreadyClaimed && _calls != null) {
          final current = _calls!;
          _calls = OpenCallList(
            items: current.items
                .where((item) => item.bookingNumber != call.bookingNumber)
                .toList(growable: false),
            blockedReason: current.blockedReason,
            message: current.message,
          );
        }
      });
      _showMessage(
        alreadyClaimed
            ? '다른 기사가 먼저 이 콜을 배정받았습니다.'
            : error.kind == ApiFailureKind.bookingTimeConflict ||
                  error.errorCode == 'DRIVER_BOOKING_TIME_CONFLICT'
            ? '기존 운행과 시간이 겹쳐 이 콜을 받을 수 없습니다.'
            : error.userMessage,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _claiming.remove(call.bookingNumber));
      _showMessage(const ApiException(ApiFailureKind.unknown).userMessage);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 콜')),
      body: _loadingStatus
          ? const Center(
              key: Key('dispatchStatusLoading'),
              child: CircularProgressIndicator(),
            )
          : _statusError != null
          ? _StatusError(error: _statusError!, onRetry: _loadStatus)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    child: SwitchListTile(
                      key: const Key('onlineToggle'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      title: Text(
                        _status!.online ? '온라인' : '오프라인',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: Text(
                        _status!.online
                            ? '새 콜을 받을 수 있습니다.'
                            : '새 콜 수신이 중지되어 있습니다.',
                      ),
                      value: _status!.online,
                      onChanged: _changingOnline ? null : _setOnline,
                    ),
                  ),
                ),
                if (_showNewCallNotice && _status!.online)
                  Material(
                    key: const Key('newCallSocketNotice'),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('새 콜이 도착해 목록을 갱신했습니다.'),
                      trailing: IconButton(
                        key: const Key('dismissNewCallSocketNotice'),
                        onPressed: () =>
                            setState(() => _showNewCallNotice = false),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                Expanded(
                  child: _status!.online
                      ? _buildOnlineContent()
                      : const Center(
                          key: Key('offlineOpenCallsNotice'),
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              '온라인으로 전환하면 새 콜을 볼 수 있습니다',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildOnlineContent() {
    if (_loadingCalls && _calls == null) {
      return const Center(
        key: Key('openCallsLoading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_callsError case final error?) {
      return Center(
        key: const Key('openCallsError'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.userMessage, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadCalls, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final calls = _calls;
    if (calls == null || calls.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCalls,
        child: ListView(
          key: const Key('openCallsEmpty'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            const Icon(Icons.campaign_outlined, size: 52),
            const SizedBox(height: 12),
            Center(
              child: Text(
                calls?.message ?? '현재 받을 수 있는 새 콜이 없습니다.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCalls,
      child: ListView.builder(
        key: const Key('openCallsList'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: calls.items.length,
        itemBuilder: (context, index) {
          final call = calls.items[index];
          return _OpenCallCard(
            call: call,
            claiming: _claiming.contains(call.bookingNumber),
            onTap: () => _selectCall(call),
          );
        },
      ),
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('dispatchStatusError'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.userMessage, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}

class _OpenCallCard extends StatelessWidget {
  const _OpenCallCard({
    required this.call,
    required this.claiming,
    required this.onTap,
  });

  final OpenCall call;
  final bool claiming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheduled = _formatDateTime(call.scheduledPickupAt);
    final matchLabel = call.isExactVehicleMatch
        ? '${call.vehicleMatchType} · 정확 일치'
        : '${call.vehicleMatchType} · 호환 업그레이드';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('openCall-${call.bookingNumber}'),
        onTap: claiming ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scheduled ?? '${call.pickupDate} ${call.pickupTime}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Chip(
                    key: Key('vehicleMatch-${call.bookingNumber}'),
                    label: Text(matchLabel),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                AirportLabelResolver.displayLabelFor(call.origin),
                key: Key('openCallOrigin-${call.bookingNumber}'),
              ),
              const SizedBox(height: 6),
              Text(
                AirportLabelResolver.displayLabelFor(call.destination),
                key: Key('openCallDestination-${call.bookingNumber}'),
              ),
              const SizedBox(height: 10),
              Text('${call.vehicleTypeName} · ${call.passengerCount}명'),
              if (claiming) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _formatDateTime(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  final bangkok = hasTimeZone
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  return '${bangkok.year.toString().padLeft(4, '0')}-'
      '${bangkok.month.toString().padLeft(2, '0')}-'
      '${bangkok.day.toString().padLeft(2, '0')} '
      '${bangkok.hour.toString().padLeft(2, '0')}:'
      '${bangkok.minute.toString().padLeft(2, '0')}';
}
