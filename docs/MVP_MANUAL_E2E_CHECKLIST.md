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

- [ ] Backend tests pass
- [ ] Frontend tests pass

---

## Sign-off

| Role | Name | Date | Pass |
|------|------|------|------|
| Operator | | | [ ] |
| Engineering | | | [ ] |

Notes:

_______________________________________________

_______________________________________________
