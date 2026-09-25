# Isolated admin manual booking verification

`run.cjs` sends real HTTP requests to the application and persists changes in a
disposable MariaDB database. It does not replace services with mocks.

## Safety and prerequisites

- Never run this against a live booking database. The script requires
  `DB_HOST=tride-qa-admin-db` and `DB_NAME=tride_qa_admin` and rejects non-QA users.
- Use a dedicated Docker **internal** network, with no published ports, no
  production mounts, and no SMTP/Firebase/OAuth credentials. Use fresh JWT and
  database secrets, not production credentials.
- Import schema **including triggers**, and only the `service_categories`,
  `service_types`, and `vehicle_types` catalog rows. Do not copy customers,
  drivers, tokens, devices, bookings, or other operational data.
- Change imported trigger definers to `CURRENT_USER` in this disposable database
  only. Price aggregation relies on the database triggers.
- Start an isolated container using the deployed backend image and QA-only
  environment. The script creates synthetic admin/driver accounts in an empty
  QA database. Phone `1111111` is a synthetic fixture, not the live driver row.

## Execution

From the backend working directory in that container, run `node` with this file
on standard input (or `node /path/to/run.cjs`). It starts its own loopback HTTP
listener, uses a QA-only JWT, and closes the listener and DB pool on completion.
On repeat runs it deactivates only the synthetic driver's QA assignments.

Checks cover creation/detail, UTC+7 pickup, memo-only preservation, passenger and
luggage partial updates, flight ETA roundtrip, golf/flight preservation, driver
candidate conflicts, 60:00 rejection, and 60:01 assignment with an active job.

This is isolated HTTP/database integration verification, **not** production
reservation, notification-delivery, mobile-app, or browser E2E verification.
Stop the temporary containers after use. Never clean up a production booking to
remove a QA fixture; these fixtures exist only in the disposable database.
