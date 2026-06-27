# Driver UX Flow

Operational guide for the TTaxi **driver web** experience (`/driver`). Native apps, live GPS, maps, and push notifications are out of scope.

## Role

Drivers use JWT login (`driver_access_token` in browser storage). They see only bookings with an **active assignment** to their account. Admin and customer tokens are never reused.

## Login

1. Open `/driver`.
2. Enter email and password.
3. On success → **Jobs** tab (default shell).
4. Invalid credentials show the API error on the form.
5. Missing or expired token on any API call → redirect to login; only `driver_access_token` is cleared on logout.

## Main navigation

Bottom bar (max four destinations):

| Tab | Purpose |
|-----|---------|
| **Jobs** | Today’s assigned pickups (default) |
| **Notifications** | Assignment, chat, settlement alerts |
| **Settlement** | Commission obligations and receipts |
| **Profile** | Rating summary and logout |

No statistics dashboard.

## Job grouping (Jobs tab)

Today’s list is grouped:

1. **Active / Current** — `DRIVER_ASSIGNED`, `DRIVER_ARRIVED`, `PICKED_UP`
2. **Upcoming** — other non-terminal statuses (e.g. `CONFIRMED`)
3. **Completed** — `COMPLETED`, `CANCELLED`, `NO_SHOW`

Active jobs appear first. Each card shows booking number, status, pickup time, route, customer name, vehicle, passengers, next action hint, and opens booking detail.

Pull-to-refresh and app-bar refresh reload the list. Returning from detail refreshes jobs.

## Booking detail

Information order: status and next action → pickup time → route → customer (call when allowed) → passengers/luggage → flight (if any) → special requests → chat → settlement (after `COMPLETED`).

One **primary bottom action** at a time when the backend allows it.

## Status → visible action

Server `allowedActions` and status are the source of truth. No invented lifecycle states.

| Status | Primary action | Notes |
|--------|----------------|-------|
| `PENDING` / `CONFIRMED` | None | Unless assigned workflow applies |
| `DRIVER_ASSIGNED` | **Mark arrived** | When `MARK_ARRIVED` in `allowedActions` |
| `DRIVER_ARRIVED` | **Scan boarding QR** | Customer’s boarding QR |
| `PICKED_UP` | **Scan dropoff QR** | Customer’s dropoff QR |
| `COMPLETED` | None | Settlement section shown |
| `CANCELLED` / `NO_SHOW` | None | Read-only terminal state |

APIs:

- `POST /api/v1/driver/bookings/:bookingNumber/arrive`
- `POST /api/v1/driver/bookings/:bookingNumber/scan-boarding`
- `POST /api/v1/driver/bookings/:bookingNumber/scan-dropoff`

## QR workflow

- **Boarding** — driver scans QR shown by customer at pickup.
- **Dropoff** — driver scans customer dropoff QR after trip starts.
- Bottom sheet: camera (native) or manual token entry (web default).
- Wrong/expired QR shows error; duplicate scans blocked server-side.
- Success refreshes detail; completed bookings cannot scan again.
- Raw QR tokens are not displayed in the UI.

## Chat

Booking-scoped chat from detail (app bar or section). Unread count on detail. Terminal bookings are read-only. Reassigned drivers lose access per server rules. Driver chat uses `driver_access_token` only.

## Notifications

List with refresh, mark read, mark all read. Tap opens booking detail or settlement when `bookingNumber` is in payload; otherwise safe fallback message. No push delivery in this phase.

## Settlement

After `COMPLETED`, detail shows commission amount and status; full receipt flow on Settlement tab and detail page.

- Receipt upload with file type/size validation
- Loading during upload; duplicate submit prevention
- Rejection reason when present
- No payment gateway or wallet

## Terminal states

`COMPLETED`, `CANCELLED`, `NO_SHOW` — no trip status actions. Call button hidden when not operationally relevant.

## Deferred features

- Live GPS / “on route” tracking
- Maps and navigation
- Automatic dispatch
- Push notifications
- WhatsApp / SMS shortcuts
- Earnings analytics and complex reports
- Native Android/iOS driver apps
