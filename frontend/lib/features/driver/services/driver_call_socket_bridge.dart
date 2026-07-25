import 'driver_urgent_negotiation_controller.dart';

typedef DriverUrgentSocketEventHandler =
    void Function(String event, Map<String, dynamic> payload);

/// Lightweight bridge so [DriverJobsPage] can react to urgent socket events
/// while the socket connection lives in [DriverTodayPage] or the shell.
class DriverCallSocketBridge {
  DriverCallSocketBridge._();

  static final instance = DriverCallSocketBridge._();

  DriverUrgentSocketEventHandler? onUrgentEvent;

  void dispatch(String event, Map<String, dynamic> payload) {
    DriverUrgentNegotiationController.instance.handleSocketEvent(event, payload);
    onUrgentEvent?.call(event, payload);
  }
}
