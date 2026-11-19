-- Export administrator-entered expiry dates before rollback if they are needed.
ALTER TABLE driver_vehicles DROP COLUMN insurance_expires_on;
