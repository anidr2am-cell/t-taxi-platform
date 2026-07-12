# MVP Demo Guide

## Local Verification

```powershell
cd C:\TTaxi\backend
npm install
npm test

cd C:\TTaxi\frontend
flutter pub get
flutter test
flutter run -d chrome --web-port=8080
```

Use a dedicated local database. Never point local scripts at legacy `ttaxi` or production data.

## Demo Sequence

1. Customer creates a booking and records the booking number.
2. Admin opens Needs action and assigns a driver.
3. Driver opens Today and performs Start route, Arrived, Customer picked up, and End trip.
4. Confirm booking is `SETTLEMENT_PENDING`, not completed.
5. Driver uploads a transfer slip for the fixed 200 THB commission.
6. Admin previews the slip and approves payment.
7. Confirm booking is `COMPLETED` and commission is `PAID`.
8. Customer submits a rating, tags, and optional comment.
9. Admin verifies review detail and adds an append-only internal note.

Customer/driver QR guidance must not appear in the commercial demo. QR internals are compatibility-only.

## Privacy Checks

- Customer: no commission, receipt, admin note, or operations issue data.
- Driver: no raw review comment, negative tags, admin note, or another driver's booking.
- Guest access: scoped token and booking ownership rules remain enforced.
