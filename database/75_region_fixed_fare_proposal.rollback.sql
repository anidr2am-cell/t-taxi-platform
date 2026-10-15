-- Export administrator boundary edits before rollback. Disable REGION_FIXED_FARES_ENABLED first.
DROP TABLE IF EXISTS pricing_regions;
-- Existing routes, prices, bookings, capacity rules were not changed.
