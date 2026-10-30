# Customer contact selection and optional booking email

## User-facing changes

- Customer step 4 uses one dropdown: KakaoTalk, LINE, WhatsApp, WeChat, Telegram. Five choices fit a narrow mobile viewport without a tall grid. SMS is removed only from new selection; old SMS reservations and older clients remain supported.
- All new selections keep the existing required E.164 phone policy. LINE retains required ID; Kakao, WeChat and Telegram IDs are optional. WhatsApp uses the phone as its messenger ID. Draft SMS selections migrate to WhatsApp while keeping the phone; historical reservation labels are not rewritten.
- Optional email has an explanation, keyboard/autofill support, validation, draft persistence and an explicit `customer.email` create-request field. Empty email is omitted. The backend already stores this field; merely collecting an address does not resend old mail or change notification policy.
- Five-language guide says receipt **or trip statement**, since an unpaid trip cannot be described as paid. The three-message/driver-confirmation email policy is a separate PR (#195).
- WeChat uses the unmodified owner-supplied `21718.jpg`, served through the existing settings image route. The full image is contained, not cropped. Telegram uses `https://t.me/TRider_taxi`. Preferred-channel resolution supports both, retaining the existing truthful fallback when a channel is disabled.
- Customer-facing confirmation/handoff uses the same channels; the user still explicitly sends their booking reference. No customer contact is exposed to drivers. No font, renderer, Flutter index, fare, capacity, payment or dispatch change.

## Migration 78 (not applied to production)

`database/78_customer_messenger_channels.sql` expands only `booking_contact_connections.channel` with TELEGRAM and sets up the two channels. It preserves affected setting rows in `migration_78_contact_settings_backup`, enables WeChat/Telegram, stores the supplied Telegram link, and clears an old custom WeChat QR path so the new bundled original is used. Existing connection/reservation/payment/assignment/email rows are untouched.

Rollback file: `database/rollback_78_customer_messenger_channels.sql`. Restore original settings and enum only if **no Telegram connection rows exist**. Otherwise the SQL refuses to proceed: roll back code only, retain the expanded enum/history, and decide follow-up separately. Never delete or convert existing history to make rollback pass. Snapshot backup is retained for audit/reapplication.

On eventual approval: existing scope checks, DB+uploads backup/SHA/Drive verification; confirm current enum and affected settings, apply 78, then backend → frontend with --no-deps. Do not restart DB/proxy, send mail or create a production booking. Apply to isolated QA first; no production changes are authorized by this implementation.

## Preview verification boundary

The isolated preview has a unique backend/network and X-Preview-Backend header. Its API exposes real channel settings and the actual bundled QR; mutating requests are blocked. Mobile step-4 views resume synthetic local draft data. A connection-page screenshot may use a virtual QA reservation response only; it never represents a created real booking. Unit/widget tests cover persistence/validation; the isolated DB covers migration apply/rollback/reapply and refusal when Telegram history exists.
