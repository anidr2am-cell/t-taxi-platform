-- Restore original prices; deactivate only new prices and new routes.
-- Never delete routes/prices, so bookings referencing them remain valid.
-- Keep migration_73_fares_backup for audit and reapplication. No capacity changes.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP PROCEDURE IF EXISTS rollback_fare_migration_73;
DELIMITER //
CREATE PROCEDURE rollback_fare_migration_73()
BEGIN
 DECLARE n INT DEFAULT 0;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT COUNT(*) INTO n FROM migration_73_fares_backup;
 IF n<>36 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 rollback STOP: backup must contain 36 targets'; END IF;
 SELECT COUNT(*) INTO n FROM migration_73_fares_backup WHERE applied=1;
 IF n=36 THEN
  SELECT COUNT(*) INTO n FROM migration_73_fares_backup b JOIN vehicle_prices vp ON vp.id=b.applied_price_id
   WHERE vp.price=b.new_price AND vp.is_active=1 AND vp.deleted_at IS NULL;
  IF n<>36 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 rollback STOP: current prices changed independently'; END IF;
  UPDATE vehicle_prices vp JOIN migration_73_fares_backup b ON vp.id=b.old_price_id
   SET vp.price=b.old_price,vp.is_active=b.old_price_active,vp.updated_at=b.old_price_updated_at;
  UPDATE vehicle_prices vp JOIN migration_73_fares_backup b ON vp.id=b.applied_price_id SET vp.is_active=0 WHERE b.old_price_id IS NULL;
  UPDATE routes r JOIN migration_73_fares_backup b ON r.id=b.applied_route_id SET r.is_active=0 WHERE b.old_route_id IS NULL;
  UPDATE migration_73_fares_backup SET applied=0;
 ELSEIF n<>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='73 rollback STOP: partial application state';
 END IF;
 COMMIT;
END//
DELIMITER ;
CALL rollback_fare_migration_73();
DROP PROCEDURE rollback_fare_migration_73;
