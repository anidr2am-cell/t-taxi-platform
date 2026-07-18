# Synthetic settlement receipt retention

This note documents the current retention behavior for synthetic E2E
settlement receipts. It is intentionally documentation-only: no migration,
storage job, deletion API, or server behavior is changed here.

## Current implementation

Settlement receipt uploads use the existing driver settlement upload endpoint:

```text
POST /api/v1/driver/settlements/:bookingNumber/receipt
multipart field: file
```

The backend stores the uploaded file under the configured upload directory:

```text
{UPLOAD_DIR}/settlements/{bookingNumber}/{generated-file-name}
```

The metadata is inserted into `files` with:

- `entity_type = COMMISSION_RECEIPT`
- `entity_id = bookings.id`
- `storage_provider = LOCAL`
- relative `file_path`
- MIME type, size, original filename, uploader, and audit fields

The active receipt is referenced by:

```text
bookings.commission_receipt_file_id
```

## Access control

Receipt files are not served as public static assets.

Downloads go through authenticated API endpoints:

- driver: `GET /api/v1/driver/settlements/:bookingNumber/receipt`
- admin: `GET /api/v1/admin/settlements/:bookingNumber/receipt`

The service allows:

- the owning assigned driver for the booking;
- `ADMIN`;
- `SUPER_ADMIN`.

Other users receive `403` or `404` style responses and do not get a storage
path. The API returns file bytes through `sendFile` only after checking the
booking, active `commission_receipt_file_id`, file row, ownership/role, and
path containment under `UPLOAD_DIR`.

## Replacement and rejection behavior

When a driver uploads a replacement receipt before approval:

1. a new file is copied into `UPLOAD_DIR`;
2. a new `files` row is inserted;
3. `bookings.commission_receipt_file_id` is updated to the new file ID;
4. the previous file row is soft-deleted with `files.deleted_at`.

When an admin rejects a submitted receipt:

1. the active file row is soft-deleted;
2. `bookings.commission_receipt_file_id` is cleared;
3. the rejection reason is stored in booking metadata;
4. an activity log is written.

In both cases, the current code soft-deletes the DB metadata row. It does not
remove the physical file from disk.

## E2E cleanup behavior

The staging E2E runners archive synthetic booking fixtures through the admin
booking archive API after validating the booking number, `[E2E]` customer name,
marker, and run ID.

Archiving a booking does not delete related child data and does not physically
delete receipt files. This is intentional today because the archive feature is
used as a reversible administrative visibility control, not as a destructive
storage cleanup process.

Synthetic receipt files are small runtime-generated PNGs containing only E2E
text such as:

- `E2E TEST RECEIPT`
- `NOT A REAL PAYMENT`
- the synthetic run ID

They must never contain real bank data, real customer information, phone
numbers, access tokens, QR payloads, or production payment artifacts.

## Operational retention policy for staging

Until a dedicated storage cleanup job exists, staging operators should treat
synthetic receipt files as normal application uploads with a manual retention
review.

Recommended review:

1. Confirm the booking is archived and clearly synthetic:
   - customer name starts with `[E2E]`;
   - marker contains the runner marker and run ID;
   - booking number matches the test manifest.
2. Confirm there is no active `bookings.commission_receipt_file_id` pointing to
   the file row if considering physical deletion.
3. Confirm the file row is soft-deleted or the booking is already archived and
   no operational investigation needs the file.
4. Remove files only through an approved operations procedure that records:
   - booking number;
   - file ID;
   - storage path;
   - operator;
   - timestamp;
   - reason.

Do not manually delete receipt files for non-E2E bookings as part of staging
test cleanup.

## Future safe cleanup job requirements

A future automated cleanup job should be implemented separately and reviewed
before use. Minimum safeguards:

- run only in staging unless explicitly designed for production retention;
- dry-run mode by default;
- require `[E2E]` customer name and known E2E marker;
- require archived booking or soft-deleted file row;
- refuse active `commission_receipt_file_id` references;
- never touch KTaxi/88taxi paths or containers;
- produce an audit manifest;
- delete only files below the configured `UPLOAD_DIR`;
- never log tokens, passwords, phone numbers, bank details, or raw receipt
  contents.

## Current conclusion

There is no existing safe destructive receipt deletion API or retention worker
for synthetic receipts. The safe current behavior is:

- archive the synthetic booking fixture;
- rely on authenticated receipt access controls;
- keep physical upload cleanup as a documented manual/operations follow-up.
