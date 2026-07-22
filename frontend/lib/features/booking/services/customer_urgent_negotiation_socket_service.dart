import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';
import '../models/urgent_negotiation_status.dart';

typedef UrgentNegotiationEventHandler = void Function(Map<String, dynamic> payload);

class CustomerUrgentNegotiationSocketService {
  io.Socket? _socket;
  String? _subscribedBookingNumber;
  int? _subscribedBookingId;

  UrgentNegotiationEventHandler? onEtaProposed;
  UrgentNegotiationEventHandler? onConfirmed;
  UrgentNegotiationEventHandler? onCancelled;
  UrgentNegotiationEventHandler? onExpired;
  UrgentNegotiationEventHandler? onSubscribed;

  bool get isConnected => _socket?.connected == true;

  io.Socket connect({String? accessToken, String? guestAccessToken}) {
    if (_socket != null) {
      _detachListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    final auth = <String, dynamic>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      auth['token'] = accessToken;
    } else if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      auth['guestAccessToken'] = guestAccessToken;
    }

    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth(auth)
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      if (_subscribedBookingNumber != null) {
        subscribe(_subscribedBookingNumber!);
      }
    });

    _socket!.onReconnect((_) {
      if (_subscribedBookingNumber != null) {
        subscribe(_subscribedBookingNumber!);
      }
    });

    _registerEvent('booking:urgent-negotiation:eta-proposed', onEtaProposed);
    _registerEvent('booking:urgent-negotiation:confirmed', onConfirmed);
    _registerEvent('booking:urgent-negotiation:cancelled', onCancelled);
    _registerEvent('booking:urgent-negotiation:expired', onExpired);
    _registerEvent('booking:urgent-negotiation:subscribed', (payload) {
      final statusRaw = payload['status'];
      if (statusRaw is Map) {
        onSubscribed?.call(Map<String, dynamic>.from(statusRaw));
      } else {
        onSubscribed?.call(payload);
      }
    });

    return _socket!;
  }

  void _registerEvent(String event, UrgentNegotiationEventHandler? handler) {
    _socket?.on(event, (data) {
      if (data is Map && handler != null) {
        handler(Map<String, dynamic>.from(data));
      }
    });
  }

  Future<UrgentNegotiationStatus?> subscribe(String bookingNumber) async {
    _subscribedBookingNumber = bookingNumber;
    if (_socket == null || !_socket!.connected) return null;

    final completer = Completer<UrgentNegotiationStatus?>();
    _socket!.emitWithAck(
      'booking:urgent-negotiation:subscribe',
      {'bookingNumber': bookingNumber},
      ack: (ack) {
        if (ack is Map && ack['ok'] == true) {
          _subscribedBookingId = ack['bookingId'] as int?;
          final statusRaw = ack['status'];
          if (statusRaw is Map) {
            completer.complete(
              UrgentNegotiationStatus.fromJson(
                Map<String, dynamic>.from(statusRaw),
              ),
            );
            return;
          }
        }
        completer.complete(null);
      },
    );
    return completer.future;
  }

  void unsubscribe() {
    _socket?.emit('booking:urgent-negotiation:unsubscribe', {});
    _subscribedBookingNumber = null;
    _subscribedBookingId = null;
  }

  void _detachListeners() {
    for (final event in const [
      'booking:urgent-negotiation:eta-proposed',
      'booking:urgent-negotiation:confirmed',
      'booking:urgent-negotiation:cancelled',
      'booking:urgent-negotiation:expired',
      'booking:urgent-negotiation:subscribed',
    ]) {
      _socket?.off(event);
    }
  }

  void disconnect() {
    unsubscribe();
    _detachListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
