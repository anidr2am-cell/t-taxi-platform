# Commercialization RC Manual E2E

## Customer

- [ ] Create booking with empty country, `korea`, and `대한민국` variants
- [ ] Change passenger/luggage values repeatedly; final vehicle recommendation is current
- [ ] Look up booking and see assigned driver/trip status
- [ ] No customer QR instructions
- [ ] Review form appears in `SETTLEMENT_PENDING` or `COMPLETED`
- [ ] Submit rating 1-5, tags, optional comment; duplicate is blocked
- [ ] No commission, receipt, internal note, or admin issue data

## Driver

- [ ] Login, four tabs, Today default
- [ ] Assigned booking visible only to active driver
- [ ] Start route -> `ON_ROUTE`
- [ ] Mark arrived -> `DRIVER_ARRIVED`
- [ ] Mark picked up -> `PICKED_UP`
- [ ] End trip -> `SETTLEMENT_PENDING`
- [ ] 200 THB settlement and transfer-slip upload
- [ ] New assignment blocked before approval
- [ ] No QR menu in active UX
- [ ] No review comment, negative tags, or internal admin notes

## Admin

- [ ] Needs action, summary, issues, search, and filters
- [ ] Assign/reassign driver
- [ ] Detail order and single primary action
- [ ] Append-only internal note with author/time; no edit/delete
- [ ] Cannot approve without submitted transfer slip
- [ ] Preview slip and approve 200 THB
- [ ] Booking becomes `COMPLETED`; commission becomes `PAID`
- [ ] Rating, tags, raw comment, timestamp, and low-rating issue visible

## Infrastructure

- [ ] `tride-db`, `tride-backend`, `tride-frontend` healthy
- [ ] API 3100 and UI 3101 return success
- [ ] No raw SQL/DB errors in UI
- [ ] Legacy KTaxi unchanged
