-- Stop new backend before rollback. Backup table retained for audit.
START TRANSACTION;
UPDATE vehicle_capacity_rules r JOIN migration_77_capacity_backup b ON b.id=r.id
SET r.max_passengers=b.max_passengers, r.max_carriers_20_inch=b.max_carriers_20_inch,
 r.max_carriers_24_inch_plus=b.max_carriers_24_inch_plus, r.max_golf_bags=b.max_golf_bags,
 r.max_special_luggage=b.max_special_luggage, r.combination_constraints=NULL;
COMMIT;
-- Keep additive nullable column so code rollback is safe. Before reapply,
-- verify restored rows and archive the backup table; never overwrite it silently.
