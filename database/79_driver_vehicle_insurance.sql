-- Existing certificate files do not contain a verified structured expiry date.
-- Administrators enter the date from the insurance certificate.
ALTER TABLE driver_vehicles
  ADD COLUMN insurance_expires_on DATE NULL DEFAULT NULL;
