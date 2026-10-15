## Review requests, phase 1

Manual requests only. There is no new email, LINE, SMS or other message dispatcher, scheduler or notification-outbox event.

- `operations.googleReviewUrl` is optional and HTTPS-only. Configure it from administrator settings. No production default is shipped.
- Both customer review choices use the existing server eligibility: `SETTLEMENT_PENDING` or `COMPLETED`, with an assigned/historical driver. Google remains visible independently of rating or submission.
- New customer bookings save `metadata.locale`; the selected booking language also updates the signed-in user's locale in the same transaction.
- Actual trip-end transitions set `metadata.reviewRequestEligibleAt` once. The request queue requires this marker, so historical ended bookings are never backfilled. Settlement approval alone does not create the marker.
- Manual tracking uses `metadata.reviewRequest` and booking activity logs. Copy does not imply send. Re-sending requires explicit confirmation. Opt-out removes the booking from the queue. `contact_status` is untouched.
- Lookup links include booking number and language only, never a guest-access token or telephone number. The existing guest/member authentication remains required.
- No schema migration. Rollback is a code rollback; the additional metadata/settings can remain safely stored.

### Isolated preview

Dedicated network and uniquely named backend, identified by `X-Preview-Backend`. No connection to `tride-prod-net`. SMTP/FCM delivery configuration is disabled. Only synthetic QA accounts and three QA bookings are present. Credentials are stored in the root-only file `/root/tride-review-request-preview-credentials.txt`; do not paste its contents into reports.

### Later email automation (not implemented)

Use a separate, idempotent request outbox keyed by booking/channel, an explicit launch cutoff and opt-out checks. Schedule relative to actual trip end, not commission settlement completion; consider two hours after completion with a Bangkok quiet-hours window. Reuse the existing SMTP adapter after verifying configuration and consent. Distinguish queued/sent/delivered/failed; retain manual tracking and prevent duplicate manual/automatic requests. Do not infer a Google review completion from a click. LINE requires provider compatibility, a stored Messaging API recipient ID and official-account friendship; social login alone is insufficient.
