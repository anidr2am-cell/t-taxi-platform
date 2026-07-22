import 'package:flutter/foundation.dart';

enum DriverUrgentNegotiationBannerPhase {
  hidden,
  awaitingCustomer,
  confirmed,
  cancelled,
  roundEnded,
  etaLockExpired,
}

class DriverUrgentNegotiationState {
  const DriverUrgentNegotiationState({
    this.bookingNumber,
    this.phase = DriverUrgentNegotiationBannerPhase.hidden,
    this.expiresAt,
  });

  final String? bookingNumber;
  final DriverUrgentNegotiationBannerPhase phase;
  final String? expiresAt;

  bool matchesBooking(String? bookingNumber) {
    if (phase == DriverUrgentNegotiationBannerPhase.hidden) return false;
    if (bookingNumber == null || bookingNumber.isEmpty) return true;
    return this.bookingNumber == bookingNumber;
  }
}

class DriverUrgentNegotiationController extends ChangeNotifier {
  DriverUrgentNegotiationController._();

  static final instance = DriverUrgentNegotiationController._();

  DriverUrgentNegotiationState _state = const DriverUrgentNegotiationState();
  DriverUrgentNegotiationState get state => _state;

  void startAwaitingCustomer({
    required String bookingNumber,
    required String customerDecisionExpiresAt,
  }) {
    _state = DriverUrgentNegotiationState(
      bookingNumber: bookingNumber,
      phase: DriverUrgentNegotiationBannerPhase.awaitingCustomer,
      expiresAt: customerDecisionExpiresAt,
    );
    notifyListeners();
  }

  void showMessagePhase(
    String bookingNumber,
    DriverUrgentNegotiationBannerPhase phase,
  ) {
    if (phase == DriverUrgentNegotiationBannerPhase.hidden ||
        phase == DriverUrgentNegotiationBannerPhase.awaitingCustomer) {
      return;
    }
    _state = DriverUrgentNegotiationState(
      bookingNumber: bookingNumber,
      phase: phase,
    );
    notifyListeners();
  }

  void clear({String? bookingNumber}) {
    if (bookingNumber != null &&
        bookingNumber.isNotEmpty &&
        _state.bookingNumber != bookingNumber) {
      return;
    }
    _state = const DriverUrgentNegotiationState();
    notifyListeners();
  }

  void handleSocketEvent(String event, Map<String, dynamic> payload) {
    final bookingNumber = payload['bookingNumber']?.toString();
    if (bookingNumber == null || bookingNumber.isEmpty) return;

    switch (event) {
      case 'confirmed':
        showMessagePhase(
          bookingNumber,
          DriverUrgentNegotiationBannerPhase.confirmed,
        );
        break;
      case 'cancelled':
        showMessagePhase(
          bookingNumber,
          DriverUrgentNegotiationBannerPhase.cancelled,
        );
        break;
      case 'round-ended':
        showMessagePhase(
          bookingNumber,
          DriverUrgentNegotiationBannerPhase.roundEnded,
        );
        break;
      case 'locked':
        if (_state.bookingNumber == bookingNumber &&
            _state.phase == DriverUrgentNegotiationBannerPhase.awaitingCustomer) {
          clear(bookingNumber: bookingNumber);
        }
        break;
    }
  }
}
