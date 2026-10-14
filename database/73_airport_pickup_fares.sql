-- Migration 73: approved airport pickup base fares only. No capacity changes.
-- Run this single file, not database/migrate.sh. Back up DB first.
-- Before first application: BKK -> BANGKOK must be 550/600/1100, and the
-- two airport-to-airport AIRPORT_PICKUP routes must not exist.
-- Originals and created row IDs survive rollback for safe reapplication.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS migration_73_fares_backup (
 service_code VARCHAR(40) NOT NULL, origin_code VARCHAR(40) NOT NULL,
 destination_code VARCHAR(40) NOT NULL, vehicle_code VARCHAR(40) NOT NULL,
 old_route_id INT UNSIGNED NULL, old_price_id INT UNSIGNED NULL,
 old_price DECIMAL(12,2) NULL, old_price_active TINYINT NULL,
 old_price_updated_at DATETIME NULL, new_price DECIMAL(12,2) NOT NULL,
 applied_route_id INT UNSIGNED NULL, applied_price_id INT UNSIGNED NULL,
 applied TINYINT NOT NULL DEFAULT 0,
 PRIMARY KEY(service_code,origin_code,destination_code,vehicle_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP PROCEDURE IF EXISTS apply_fare_migration_73;
DELIMITER //
CREATE PROCEDURE apply_fare_migration_73()
BEGIN
 DECLARE n INT DEFAULT 0;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 CREATE TEMPORARY TABLE fare_73_targets AS
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'BANGKOK' destination_code, 'SEDAN' vehicle_code, 500 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'BANGKOK' destination_code, 'SUV' vehicle_code, 600 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'BANGKOK' destination_code, 'VAN' vehicle_code, 1000 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'DMK' destination_code, 'SEDAN' vehicle_code, 600 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'DMK' destination_code, 'SUV' vehicle_code, 700 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'BKK' origin_code, 'DMK' destination_code, 'VAN' vehicle_code, 1000 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'DMK' origin_code, 'BKK' destination_code, 'SEDAN' vehicle_code, 600 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'DMK' origin_code, 'BKK' destination_code, 'SUV' vehicle_code, 700 new_price
UNION ALL
SELECT 'AIRPORT_PICKUP' service_code, 'DMK' origin_code, 'BKK' destination_code, 'VAN' vehicle_code, 1000 new_price;
 SELECT COUNT(*) INTO n FROM service_types WHERE code='AIRPORT_PICKUP' AND is_active=1 AND deleted_at IS NULL;
 IF n<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: AIRPORT_PICKUP unavailable'; END IF;
 SELECT COUNT(*) INTO n FROM locations WHERE code IN ('BKK','DMK','BANGKOK') AND is_active=1 AND deleted_at IS NULL;
 IF n<>3 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: location precondition'; END IF;
 SELECT COUNT(*) INTO n FROM vehicle_types WHERE code IN ('SEDAN','SUV','VAN') AND is_active=1 AND deleted_at IS NULL;
 IF n<>3 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: active vehicle precondition'; END IF;
 SELECT COUNT(*) INTO n FROM migration_73_fares_backup;
 IF n=0 THEN
  SELECT COUNT(*) INTO n FROM routes r JOIN service_types st ON st.id=r.service_type_id
   JOIN locations lo ON lo.id=r.origin_location_id JOIN locations ld ON ld.id=r.destination_location_id
   WHERE st.code='AIRPORT_PICKUP' AND ((lo.code='BKK' AND ld.code='DMK') OR (lo.code='DMK' AND ld.code='BKK'));
  IF n<>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: airport route already exists; review before proceeding'; END IF;
  SELECT COUNT(*) INTO n FROM routes r JOIN service_types st ON st.id=r.service_type_id
   JOIN locations lo ON lo.id=r.origin_location_id JOIN locations ld ON ld.id=r.destination_location_id
   JOIN vehicle_prices vp ON vp.route_id=r.id JOIN vehicle_types vt ON vt.id=vp.vehicle_type_id
   WHERE st.code='AIRPORT_PICKUP' AND lo.code='BKK' AND ld.code='BANGKOK'
    AND r.is_active=1 AND r.deleted_at IS NULL AND vp.is_active=1 AND vp.deleted_at IS NULL
    AND vp.effective_from IS NULL AND vp.effective_to IS NULL
    AND ((vt.code='SEDAN' AND vp.price=550) OR (vt.code='SUV' AND vp.price=600) OR (vt.code='VAN' AND vp.price=1100));
  IF n<>3 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: expected BKK Bangkok prices 550/600/1100'; END IF;
  INSERT INTO migration_73_fares_backup(service_code,origin_code,destination_code,vehicle_code,old_route_id,old_price_id,old_price,old_price_active,old_price_updated_at,new_price)
   SELECT t.service_code,t.origin_code,t.destination_code,t.vehicle_code,r.id,vp.id,vp.price,vp.is_active,vp.updated_at,t.new_price
   FROM fare_73_targets t JOIN service_types st ON st.code=t.service_code
   JOIN locations lo ON lo.code=t.origin_code JOIN locations ld ON ld.code=t.destination_code
   JOIN vehicle_types vt ON vt.code=t.vehicle_code
   LEFT JOIN routes r ON r.service_type_id=st.id AND r.origin_location_id=lo.id AND r.destination_location_id=ld.id
   LEFT JOIN vehicle_prices vp ON vp.route_id=r.id AND vp.vehicle_type_id=vt.id;
 END IF;
 SELECT COUNT(*) INTO n FROM migration_73_fares_backup;
 IF n<>9 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: backup must contain 9 targets'; END IF;
 -- Refuse to overwrite a price changed independently since this migration.
 SELECT COUNT(*) INTO n FROM migration_73_fares_backup b JOIN vehicle_prices vp ON vp.id=COALESCE(b.applied_price_id,b.old_price_id)
  WHERE vp.deleted_at IS NOT NULL OR (vp.price<>b.new_price AND (b.old_price IS NULL OR vp.price<>b.old_price));
 IF n<>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 STOP: price changed independently'; END IF;
 INSERT INTO routes(service_type_id,origin_location_id,destination_location_id,is_active,display_order)
  SELECT DISTINCT st.id,lo.id,ld.id,1,90 FROM migration_73_fares_backup b
  JOIN service_types st ON st.code=b.service_code JOIN locations lo ON lo.code=b.origin_code JOIN locations ld ON ld.code=b.destination_code
  WHERE b.old_route_id IS NULL AND b.applied_route_id IS NULL;
 UPDATE migration_73_fares_backup b JOIN service_types st ON st.code=b.service_code
  JOIN locations lo ON lo.code=b.origin_code JOIN locations ld ON ld.code=b.destination_code
  JOIN routes r ON r.service_type_id=st.id AND r.origin_location_id=lo.id AND r.destination_location_id=ld.id
  SET b.applied_route_id=r.id;
 UPDATE routes r JOIN migration_73_fares_backup b ON b.applied_route_id=r.id SET r.is_active=1 WHERE b.old_route_id IS NULL;
 INSERT INTO vehicle_prices(route_id,vehicle_type_id,price,currency,is_active)
  SELECT b.applied_route_id,vt.id,b.new_price,'THB',1 FROM migration_73_fares_backup b JOIN vehicle_types vt ON vt.code=b.vehicle_code
  WHERE b.old_price_id IS NULL AND b.applied_price_id IS NULL;
 UPDATE migration_73_fares_backup b JOIN vehicle_types vt ON vt.code=b.vehicle_code
  JOIN vehicle_prices vp ON vp.route_id=b.applied_route_id AND vp.vehicle_type_id=vt.id SET b.applied_price_id=vp.id;
 UPDATE vehicle_prices vp JOIN migration_73_fares_backup b ON b.applied_price_id=vp.id SET vp.price=b.new_price,vp.is_active=1;
 UPDATE migration_73_fares_backup SET applied=1;
 DROP TEMPORARY TABLE fare_73_targets;
 COMMIT;
END//
DELIMITER ;
CALL apply_fare_migration_73();
DROP PROCEDURE apply_fare_migration_73;
