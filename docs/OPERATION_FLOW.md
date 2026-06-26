# Booking Lifecycle

Booking statuses:

- PENDING
- CONFIRMED
- DRIVER_ASSIGNED
- DRIVER_ARRIVED
- PICKED_UP
- COMPLETED
- CANCELLED
- NO_SHOW

All status transitions must pass through `BookingStatusService`. Controllers and route handlers must not update booking status directly.

# QR Operation Flow

Booking created
-> boarding QR available
-> driver scans boarding QR
-> booking becomes PICKED_UP
-> boarding QR becomes unusable
-> dropoff QR becomes available
-> driver scans dropoff QR
-> booking becomes COMPLETED
-> dropoff QR becomes unusable

Repository evidence: booking creation currently issues a boarding QR token. Full driver QR scan endpoints and dropoff QR service behavior may still be pending.

# Payment

Customer pays the driver directly at destination.

Payment model: `PAY_DRIVER`.

No online payment in MVP.

# Commission

After COMPLETED, the driver owes the platform commission.

Repository evidence shows commission status fields on bookings. Receipt upload, admin approval, and driver blocking are later implementation stages unless already present in code.

# Assignment

Manual admin assignment is the MVP direction.

Automatic assignment is Phase 2.

# Reviews

Review request occurs after COMPLETED.

Full review implementation may be pending.

# Notifications

Intended event points:

- booking created
- booking confirmed
- driver assigned
- driver arrived
- boarding completed
- trip completed
- commission required
- review requested

Domain events should be used instead of direct service coupling.

# MVP and Phase 2

Currently implemented or partially implemented, based on repository evidence:

- Booking creation with PENDING status.
- Route-based pricing and vehicle recommendation services.
- Guest access token creation for guest bookings.
- Boarding QR token creation on booking create.
- Booking lifecycle transitions through `BookingStatusService`.
- Public flight lookup through `/api/v1/public/flights/search`.
- Domain event constants and in-process event bus.

Planned or not fully implemented yet:

- Full guest/member booking retrieval flow.
- Driver QR scan endpoints for boarding and dropoff.
- Dropoff QR generation service after pickup.
- Driver assignment API and assignment workflow.
- Notification delivery service wired to domain events.
- Commission receipt upload, admin approval, and driver blocking.
- Review service and review request delivery.
- Automatic driver assignment.
