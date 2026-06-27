USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_apply_driver_assignment_constraints;

DELIMITER $$

CREATE PROCEDURE sp_apply_driver_assignment_constraints()
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'booking_driver_assignments'
      AND INDEX_NAME = 'uk_bda_one_active_per_booking'
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'booking_driver_assignments'
        AND COLUMN_NAME = 'active_booking_key'
    ) THEN
      ALTER TABLE booking_driver_assignments
        ADD UNIQUE KEY uk_bda_one_active_per_booking (active_booking_key);
    ELSE
      CREATE UNIQUE INDEX uk_bda_one_active_per_booking
        ON booking_driver_assignments (
          (IF(is_active = 1 AND deleted_at IS NULL, booking_id, NULL))
        );
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'booking_driver_assignments'
      AND CONSTRAINT_NAME = 'chk_bda_active_state'
      AND CONSTRAINT_TYPE = 'CHECK'
  ) THEN
    ALTER TABLE booking_driver_assignments
      ADD CONSTRAINT chk_bda_active_state CHECK (
        is_active <> 1
        OR deleted_at IS NOT NULL
        OR (
          unassigned_at IS NULL
          AND status IN ('ASSIGNED', 'ACCEPTED')
        )
      );
  END IF;
END$$

DELIMITER ;

CALL sp_apply_driver_assignment_constraints();

DROP PROCEDURE IF EXISTS sp_apply_driver_assignment_constraints;

DROP TRIGGER IF EXISTS trg_bda_before_insert_validate;
DROP TRIGGER IF EXISTS trg_bda_before_update_validate;
DROP TRIGGER IF EXISTS trg_bda_after_insert_sync_booking;
DROP TRIGGER IF EXISTS trg_bda_after_update_sync_booking;
DROP TRIGGER IF EXISTS trg_bookings_driver_id_before_update;
DROP TRIGGER IF EXISTS trg_bookings_driver_id_before_insert;

DELIMITER $$

CREATE TRIGGER trg_bda_before_insert_validate
BEFORE INSERT ON booking_driver_assignments
FOR EACH ROW
BEGIN
  IF NEW.is_active = 1 AND NEW.deleted_at IS NULL THEN
    IF NEW.unassigned_at IS NOT NULL
       OR NEW.status NOT IN ('ASSIGNED', 'ACCEPTED') THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Active assignment requires unassigned_at IS NULL and status ASSIGNED or ACCEPTED';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_bda_before_update_validate
BEFORE UPDATE ON booking_driver_assignments
FOR EACH ROW
BEGIN
  IF NEW.is_active = 1 AND NEW.deleted_at IS NULL THEN
    IF NEW.unassigned_at IS NOT NULL
       OR NEW.status NOT IN ('ASSIGNED', 'ACCEPTED') THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Active assignment requires unassigned_at IS NULL and status ASSIGNED or ACCEPTED';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_bda_after_insert_sync_booking
AFTER INSERT ON booking_driver_assignments
FOR EACH ROW
BEGIN
  IF NEW.is_active = 1 AND NEW.deleted_at IS NULL THEN
    UPDATE bookings
    SET driver_id = NEW.driver_id
    WHERE id = NEW.booking_id;
  END IF;
END$$

CREATE TRIGGER trg_bda_after_update_sync_booking
AFTER UPDATE ON booking_driver_assignments
FOR EACH ROW
BEGIN
  IF NEW.is_active = 1 AND NEW.deleted_at IS NULL THEN
    UPDATE bookings
    SET driver_id = NEW.driver_id
    WHERE id = NEW.booking_id;
  ELSEIF OLD.is_active = 1 AND (NEW.is_active = 0 OR NEW.deleted_at IS NOT NULL) THEN
    UPDATE bookings
    SET driver_id = NULL
    WHERE id = NEW.booking_id
      AND driver_id <=> OLD.driver_id
      AND NOT EXISTS (
        SELECT 1
        FROM booking_driver_assignments bda
        WHERE bda.booking_id = NEW.booking_id
          AND bda.id <> NEW.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
      );
  END IF;
END$$

CREATE TRIGGER trg_bookings_driver_id_before_insert
BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
  IF NEW.driver_id IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'bookings.driver_id must be set via active assignment';
  END IF;
END$$

CREATE TRIGGER trg_bookings_driver_id_before_update
BEFORE UPDATE ON bookings
FOR EACH ROW
BEGIN
  DECLARE v_active_driver BIGINT UNSIGNED DEFAULT NULL;

  IF NOT (NEW.driver_id <=> OLD.driver_id) THEN
    SELECT bda.driver_id INTO v_active_driver
    FROM booking_driver_assignments bda
    WHERE bda.booking_id = NEW.id
      AND bda.is_active = 1
      AND bda.deleted_at IS NULL
    LIMIT 1;

    IF v_active_driver IS NOT NULL THEN
      IF NEW.driver_id IS NULL OR NEW.driver_id <> v_active_driver THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'bookings.driver_id must match active assignment driver_id';
      END IF;
    ELSEIF NEW.driver_id IS NOT NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'bookings.driver_id requires an active assignment';
    END IF;
  END IF;
END$$

DELIMITER ;
