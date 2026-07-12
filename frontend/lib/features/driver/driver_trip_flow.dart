import 'driver_ux.dart';
import 'models/driver_booking.dart';

/// Maps driver booking status to the single primary trip action key.
class DriverTripFlow {
  DriverTripFlow._();

  static const actionOrder = [
    'START_ON_ROUTE',
    'MARK_ARRIVED',
    'MARK_PICKED_UP',
    'END_TRIP',
  ];

  static String? primaryActionToken(DriverBooking booking) {
    if (DriverUx.isReadOnly(booking.status)) return null;
    for (final action in actionOrder) {
      if (booking.allowedActions.contains(action)) return action;
    }
    return null;
  }

  static String? primaryActionLabelKey(DriverBooking booking) {
    return switch (primaryActionToken(booking)) {
      'START_ON_ROUTE' => 'driver_action_start_on_route',
      'MARK_ARRIVED' => 'driver_action_mark_arrived',
      'MARK_PICKED_UP' => 'driver_action_mark_picked_up',
      'END_TRIP' => 'driver_action_end_trip',
      _ => null,
    };
  }

  static String? confirmTitleKey(String? actionToken) {
    return switch (actionToken) {
      'START_ON_ROUTE' => 'driver_confirm_start_on_route_title',
      'MARK_ARRIVED' => 'driver_confirm_mark_arrived_title',
      'MARK_PICKED_UP' => 'driver_confirm_mark_picked_up_title',
      'END_TRIP' => 'driver_confirm_end_trip_title',
      _ => null,
    };
  }

  static String? confirmMessageKey(String? actionToken) {
    return switch (actionToken) {
      'START_ON_ROUTE' => 'driver_confirm_start_on_route_message',
      'MARK_ARRIVED' => 'driver_confirm_mark_arrived_message',
      'MARK_PICKED_UP' => 'driver_confirm_mark_picked_up_message',
      'END_TRIP' => 'driver_confirm_end_trip_message',
      _ => null,
    };
  }

  static String? confirmButtonKey(String? actionToken) {
    return switch (actionToken) {
      'START_ON_ROUTE' => 'driver_confirm_start_on_route_yes',
      'MARK_ARRIVED' => 'driver_confirm_mark_arrived_yes',
      'MARK_PICKED_UP' => 'driver_confirm_mark_picked_up_yes',
      'END_TRIP' => 'driver_confirm_end_trip_yes',
      _ => null,
    };
  }

  static String? successMessageKey(String? actionToken) {
    return switch (actionToken) {
      'START_ON_ROUTE' => 'driver_success_on_route',
      'MARK_ARRIVED' => 'driver_success_arrived',
      'MARK_PICKED_UP' => 'driver_success_picked_up',
      'END_TRIP' => 'driver_success_end_trip',
      _ => null,
    };
  }
}
