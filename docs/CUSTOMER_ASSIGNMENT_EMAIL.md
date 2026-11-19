# Customer assignment confirmation email

Policy approved 2026-10-31: at most **three customer emails per booking**.

1. `BOOKING_CREATED`: reception acknowledgement.
2. `DRIVER_ASSIGNED`: booking confirmation with the currently assigned driver name and vehicle class, model, colour and plate. No driver/customer phone, email or messenger ID is rendered. Missing vehicle details direct the customer to support; never invent a plate or model. Five languages follow the existing booking-locale selection.
3. `TRIP_ENDED` (or direct trip completion): existing trip document/review email. Pre-trip cancellation uses this same terminal slot instead. Normal completion after trip end sends no additional email. No-show sends no additional email.

`BOOKING_CONFIRMED` remains EMAIL-disabled to avoid a second confirmation without driver details. Other customer event emails and all driver emails remain disabled; independent password-reset mail, admin email, IN_APP, FCM and sockets are unchanged.

## Safety and recovery

- The existing booking-row lock, historical-email cap and SMTP attempt ledger apply. Three separate slots are reception, assignment and terminal. Repeated assignment events/reassignment cannot send a second assignment email. An uncertain SMTP attempt consumes its slot and is not automatically resent; only proven non-acceptance supports existing admin-approved recovery.
- Before claiming an assignment email, recheck the active assignment and trip state under the booking lock. Changed/released/completed assignments are skipped without SMTP reservation. The selected details are read from the active assignment's driver/vehicle, not arbitrary event payload.
- Existing approved receipt mail is not replaced. Reception + assignment do not block the first terminal receipt. The admin receipt state ignores assignment deliveries when identifying an existing terminal document. Three historically consumed emails still block further sends.
- No migration, historical backfill, resend or queue-reset script. Previously skipped assignment deliveries remain skipped. Existing booking, payment, assignment, commission and receipt PDF values are not changed.
- Roll back this PR's code/images to disable new assignment emails again. Do not reset sent/reserved delivery records or email attempts.

## Validation without sending mail

Use fake repositories/SMTP transports: normal flow = 3; pre-trip cancellation after assignment = 3; no-show after assignment = 2. Concurrent/repeated assignment = 1 assignment email. Released/stale assignment = 0. Verify all five localized templates, Bangkok pickup time, escaped details, contact exclusion and admin terminal receipt eligibility after two earlier emails. Local HTML previews contain QA-only synthetic data.
