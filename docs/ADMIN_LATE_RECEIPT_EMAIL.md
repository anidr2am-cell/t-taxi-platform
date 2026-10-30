# Administrator-approved trip document email

A customer may supply an email address after their trip. On a SETTLEMENT_PENDING or COMPLETED booking, an administrator can enter the address and select ko/en/th/ja/zh, preview the exact trip document, and explicitly confirm the recipient before sending. Preview does not save the address or send email. Approval updates only bookings.customer_email and metadata.adminReceiptEmail, and writes RECEIPT_EMAIL_APPROVED to booking activity history. No migration is needed.

PAID produces a receipt; all other payment states produce a usage statement. The existing trip-end template includes the review request. No separate confirmation or extra review email is created. The booking status, assignments, pricing, commission and settlement data are not changed.

## Safety and delivery tracking

- Only administrators can use GET /api/v1/admin/bookings/:bookingNumber/receipt-email and POST /preview or /send beneath it.
- Preview approval is bound to recipient, language, current financial/route data, settings and template. Changes require a fresh preview.
- The approved recipient and message are frozen and encrypted using the existing email encryption key before SMTP processing.
- A booking-row lock and idempotency key prevent double approval. The existing email-slot ledger enforces at most two customer emails per booking.
- Previously accepted, in-flight or uncertain terminal mail blocks a new address/send. Confirmed non-acceptance must use the existing Mail needs attention recovery workflow, with its original immutable envelope.
- Only older EMAIL rows with no SMTP attempt can be superseded. Fresh booking-row checks prevent a previously loaded automatic worker from sending a stale email after approval. A late BOOKING_CREATED email is suppressed.
- This email-only notification is excluded from in-app notification lists. Existing IN_APP, FCM and socket behavior is unchanged.
- SMTP acceptance is shown as server acceptance, not proof of inbox delivery. Ambiguous responses are never retried from the booking card.

## Verification / deployment

Run backend npm test and frontend receipt/admin widget tests; review CI before merge. The isolated QA preview uses in-memory fixtures and fake acceptance, with no DB or SMTP transport. QA email input must use example.invalid. Production deployment is not authorized by this change.

## Customer payment acknowledgement

On ended trips, POST /api/v1/admin/bookings/:bookingNumber/customer-payment/confirm records customer payment separately from commission settlement. Only UNPAID/PENDING can become PAID; refunded/failed and non-ended trips are refused. Administrators must confirm receipt, provide a reason and match the displayed amount/currency. A booking-row lock makes repeated/concurrent confirmation idempotent. The only writes are payment_status, metadata.customerPaymentConfirmation, updated_by/updated_at and CUSTOMER_PAYMENT_CONFIRMED activity history. No email, notification, assignment or commission/settlement update is triggered.

The UI invalidates an old statement preview, preserves a typed email and refreshes the displayed payment state without losing the form. A fresh preview renders a receipt after confirmation. Existing accepted/in-flight/unknown delivery guards and the two-email booking limit remain enforced; payment confirmation does not authorize a replacement for an already sent statement.
