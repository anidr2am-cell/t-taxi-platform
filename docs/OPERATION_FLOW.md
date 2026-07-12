# Booking Lifecycle

```text
PENDING
-> CONFIRMED
-> DRIVER_ASSIGNED
-> ON_ROUTE
-> DRIVER_ARRIVED
-> PICKED_UP
-> SETTLEMENT_PENDING
-> COMPLETED
```

All status transitions pass through `BookingStatusService` or the established trip-flow service that delegates lifecycle changes to it.

`CANCELLED` and `NO_SHOW` are terminal alternatives.

# Driver Operation

Admin assigns a driver. The driver then uses buttons to start route, mark arrival, mark customer pickup, and end the trip. End trip does not immediately complete the booking; it creates the settlement-pending state.

Customer boarding/dropoff QR is not the current commercial UX. Remaining QR packages, schema, and endpoints are compatibility artifacts.

# Payment And Commission

The customer pays the driver directly (`PAY_DRIVER`). There is no online customer payment in the current MVP.

After trip end, the driver owes 200 THB. The driver uploads a transfer slip. Admin approval requires an attached receipt and changes the booking to `COMPLETED` with commission `PAID`. Commission and receipt details are not exposed to customers.

# Assignment

Manual and recommended admin assignment are supported. Drivers with an active or unsettled job are ineligible. Reassignment uses the same server-side eligibility rules.

# Reviews

Review submission is available for `SETTLEMENT_PENDING` and `COMPLETED` when a resolved driver exists and the booking has no prior review. One review per booking: rating 1-5, tags, and optional comment up to 500 characters.

# Notifications And Chat

Domain events are used instead of direct service coupling. Booking, assignment, trip, settlement, and review events may trigger notifications. Customer, admin, and active driver share the booking chat subject to access policy.
