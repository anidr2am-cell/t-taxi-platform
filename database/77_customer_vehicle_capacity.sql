-- Capacity rules approved 2026-10-17. 76 is already golf pricing.
-- Preserve exact old rows for rollback; no booking amounts are changed.
CREATE TABLE IF NOT EXISTS migration_77_capacity_backup AS
 SELECT * FROM vehicle_capacity_rules WHERE vehicle_type_id IN
 (SELECT id FROM vehicle_types WHERE code IN ('SEDAN','SUV','VAN'));
ALTER TABLE vehicle_capacity_rules ADD COLUMN IF NOT EXISTS combination_constraints JSON NULL;
START TRANSACTION;
UPDATE vehicle_capacity_rules r JOIN vehicle_types v ON v.id=r.vehicle_type_id
SET r.max_passengers=2, r.max_carriers_20_inch=2, r.max_carriers_24_inch_plus=1,
 r.max_golf_bags=2, r.combination_constraints=JSON_OBJECT('noLargeAtGolf',2)
WHERE v.code='SEDAN' AND r.is_active=1;
UPDATE vehicle_capacity_rules r JOIN vehicle_types v ON v.id=r.vehicle_type_id
SET r.max_passengers=3, r.max_carriers_20_inch=4, r.max_carriers_24_inch_plus=4,
 r.max_golf_bags=3, r.combination_constraints=JSON_OBJECT('maxCases',4,'maxCasesAndGolf',6)
WHERE v.code='SUV' AND r.is_active=1;
UPDATE vehicle_capacity_rules r JOIN vehicle_types v ON v.id=r.vehicle_type_id
SET r.max_passengers=8, r.max_carriers_20_inch=8, r.max_carriers_24_inch_plus=8,
 r.max_golf_bags=8, r.combination_constraints=NULL
WHERE v.code='VAN' AND r.is_active=1;
COMMIT;
