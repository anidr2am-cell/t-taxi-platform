-- Disable REGION_FIXED_FARES_ENABLED and recreate backend first.
-- Export administrator edits to both regional tables before destructive rollback.
DROP TABLE IF EXISTS pricing_region_fares;
DROP TABLE IF EXISTS pricing_regions;
-- Existing routes, vehicle_prices, bookings and capacity rules are unchanged.
