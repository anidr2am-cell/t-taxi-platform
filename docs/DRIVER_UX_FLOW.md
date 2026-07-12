# Driver UX Flow

## Navigation

The driver app has four primary tabs. `Today` is the default operational screen and shows the current assigned trip.

## Trip Actions

| Booking status | Driver action | Result |
|---|---|---|
| `DRIVER_ASSIGNED` | Start route | `ON_ROUTE` |
| `ON_ROUTE` | Mark arrived | `DRIVER_ARRIVED` |
| `DRIVER_ARRIVED` | Mark customer picked up | `PICKED_UP` |
| `PICKED_UP` | End trip | `SETTLEMENT_PENDING` |

The current commercial UX uses buttons, not customer boarding/dropoff QR scanning. Legacy QR API and DB structures may remain for compatibility but are not shown as the active driver workflow.

## Settlement

After trip end:

- Commission amount is 200 THB.
- Commission status is `DUE`.
- Driver uploads a transfer slip from settlement detail.
- Booking remains `SETTLEMENT_PENDING` while awaiting admin approval.
- Admin approval changes booking to `COMPLETED` and commission to `PAID`.
- Receipt linkage remains available after approval.
- An unsettled driver cannot receive another assignment.

## Privacy

Driver APIs and screens must not expose customer review comments, negative review tags, admin issue reasons, internal admin notes, guest tokens, receipt data for another driver, or another driver's booking.
