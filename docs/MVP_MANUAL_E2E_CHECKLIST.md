# MVP Manual E2E Checklist (Phase 6)

Manual verification for the current MVP: **guest booking → admin dispatch → driver trip flow → guest status lookup**.

Scope: no payment, no Socket.IO sync, no chat, no QR, no auto-dispatch, no live driver map.

---

## Before you start

- [ ] MySQL migrated (`database/migrate.ps1`)
- [ ] Backend running (`npm start` in `backend/`)
- [ ] Frontend running (`flutter run -d chrome` in `frontend/`)
- [ ] Demo data seeded (`npm run seed:mvp-demo` in `backend/`) **or** you will create a fresh booking in step 1
- [ ] Credentials from [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md) available

---

## A. Customer — create booking

| # | Step | Expected |
|---|------|----------|
| A1 | Open landing → **Book now** | Booking wizard loads |
| A2 | Select **Airport Pickup**, origin **BKK**, destination **Pattaya** | Route/pricing available |
| A3 | Pickup ≥ 2 hours ahead, 2 adults, SUV | Confirm enabled |
| A4 | Enter name + phone (e.g. `+66819998877`) | Validation passes |
| A5 | Submit booking | Success screen |
| A6 | **Booking number** visible and copy works | Format `TXYYYYMMDD####` |
| A7 | Status badge shows localized label (e.g. Pending) | Not raw enum string |
| A8 | **Track my booking** opens lookup with cached booking | Detail or lookup form |
| A9 | QR / chat sections **not** shown on complete page | Phase 5 default |

---

## B. Customer — guest lookup (seed or fresh booking)

| # | Step | Expected |
|---|------|----------|
| B1 | Open **Find my booking** (`/booking/lookup`) | Lookup form |
| B2 | Enter booking number + phone | Match seeded row or A4 phone |
| B3 | Trip details, payment summary shown | Origin/destination/service |
| B4 | Status badge localized | e.g. Pending, Driver Assigned |
| B5 | Status guidance banner matches status | Per-status message |
| B6 | Tap **Refresh** (AppBar) | Status updates after admin/driver actions |
| B7 | QR / chat / tracking sections **hidden** | `enableCustomerTools` off |

### Seeded status spot-check (optional)

Repeat B2–B6 for each seeded scenario from `seed:mvp-demo` output:

- [ ] PENDING (`+66820000001`)
- [ ] DRIVER_ASSIGNED (`+66820000002`)
- [ ] ON_ROUTE (`+66820000003`)
- [ ] DRIVER_ARRIVED (`+66820000004`)
- [ ] COMPLETED (`+66820000005`)
- [ ] CANCELLED (`+66820000006`)

---

## C. Admin — dispatch

| # | Step | Expected |
|---|------|----------|
| C1 | Admin app → Dispatch → login `admin@ttaxi.dev` | Queue loads |
| C2 | Find PENDING / unassigned booking | Row in queue |
| C3 | Status badge localized (not `DRIVER_ASSIGNED` raw) | Consistent labels |
| C4 | Open booking detail | Summary + allowed actions |
| C5 | **Assign driver** → select MVP Demo Driver | Status → Driver Assigned |
| C6 | Guest lookup refresh (B6) | Customer sees driver assigned guidance |

---

## D. Driver — trip flow

Login: phone `+66810000001`, password `Driver123456!`

| # | Step | Expected |
|---|------|----------|
| D1 | Jobs list shows assigned booking | Active group |
| D2 | Open booking detail | Status + actions |
| D3 | **Start on route** | Status → On the way |
| D4 | Guest refresh | On-route guidance |
| D5 | **Mark arrived** | Status → Driver arrived |
| D6 | **Complete trip** | Status → Completed |
| D7 | Detail read-only after complete | No further actions |
| D8 | Chat / QR buttons **not** shown | Phase 4 scope |

---

## E. End-to-end happy path (single booking)

Use one fresh booking from step A (not pre-seeded COMPLETED):

1. [ ] Customer creates booking (A1–A8)
2. [ ] Admin assigns driver (C5)
3. [ ] Driver: ON_ROUTE → DRIVER_ARRIVED → COMPLETED (D3–D6)
4. [ ] Customer refresh shows **Completed** + completion guidance (B6)

---

## F. Cancelled booking (seed or manual)

- [ ] Seeded CANCELLED booking shows cancelled guidance on guest lookup
- [ ] **Or** admin cancels a PENDING booking → guest refresh shows Cancelled

---

## G. Regression smoke

```powershell
cd C:\TTaxi\backend
npm test

cd C:\TTaxi\frontend
flutter test
```

- [x] Backend tests pass (428 tests, 2026-07-04)
- [x] Frontend tests pass (250 tests, 2026-07-04)

### API E2E rehearsal (optional automation)

```powershell
cd C:\TTaxi\backend
npm run seed:mvp-demo
npm run rehearsal:mvp-e2e
```

- [x] All 19 API checks passed (2026-07-04): 6 seeded status lookups + full happy path

---

## H. Phase 7 — UX polish (demo readiness)

### Customer

- [ ] Wizard: incomplete sections show validation hints before confirm
- [ ] Wizard: submit failure shows SnackBar (not silent failure)
- [ ] Complete page: booking number prominent; **Track my booking** visible
- [ ] Complete page: no QR / chat / payment UI by default
- [ ] Lookup: invalid booking number / phone shows field validation
- [ ] Lookup: not-found vs network error messages are distinct
- [ ] Lookup: refresh updates status without losing cached phone
- [ ] Lookup: cancelled/completed guidance text readable on mobile (360px)

### Admin

- [ ] Dispatch queue: empty state when no bookings match filters
- [ ] Dispatch queue: loading spinner on first load; retry on error
- [ ] Dispatch queue: status filter includes ON_ROUTE / CANCELLED / etc.
- [ ] Dispatch queue: assignment chips localized (not raw UNASSIGNED)
- [ ] Assign dialog: confirm disabled until driver selected (reassign: reason required)
- [ ] Assign dialog: empty drivers list shows helpful message
- [ ] Booking detail: status label localized in summary and basic info
- [ ] Booking detail: terminal booking hides dispatch actions

### Driver

- [ ] Jobs: empty state when no assignments today
- [ ] Jobs: error state with retry
- [ ] Detail: only one primary action per status (Start route / Mark arrived / Complete)
- [ ] Detail: COMPLETED / CANCELLED / NO_SHOW — no action buttons
- [ ] Detail: complete trip does not show error after successful completion
- [ ] Detail: load failure shows backend message + retry

### Layout

- [ ] Customer pages: no horizontal overflow at 360px width
- [ ] Admin dispatch list: readable on narrow mobile width
- [ ] Driver jobs/detail: sticky action bar does not overlap content

---

## I. Phase 8 — E2E rehearsal results (2026-07-04)

### Automated API rehearsal (`npm run rehearsal:mvp-e2e`)

| Area | Result |
|------|--------|
| Seeded PENDING → CANCELLED guest lookups | Pass (6/6) |
| Fresh booking create → assign → driver trip → guest refresh | Pass |
| Backend unit/widget tests | Pass (428 + 250) |

### Bugs fixed during rehearsal

| Issue | Fix |
|-------|-----|
| Guest lookup returned **429** after ~10 refreshes in one E2E session | Non-production rate limit raised to 30/min (`public.routes.js`) |
| Driver **GET detail 404** after completing trip (assignment deactivated) | Terminal assignment fallback in `driverJob.service.js` + `findDriverTerminalBookingByNumber` |

### Manual UI walkthrough (operator)

Sections **A–F** and **H** should still be spot-checked in Chrome before a live demo. API rehearsal validates backend routes and status transitions; UI polish (labels, layout, empty states) requires browser verification.

### Notes

- Re-running `seed:mvp-demo` creates **new** booking numbers; use the latest script output for B2 spot-checks.
- Guest lookup rate limit in **production** remains 10/min per IP (abuse protection).
- QR, chat, payment, Socket.IO, auto-dispatch remain out of scope.

---

## Sign-off

| Role | Name | Date | Pass |
|------|------|------|------|
| Operator | | | [ ] |
| Engineering | | | [ ] |

Notes:

_______________________________________________

_______________________________________________
