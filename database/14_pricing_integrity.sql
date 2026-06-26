USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_migrate_legacy_admin_notes;

DELIMITER $$

CREATE PROCEDURE sp_migrate_legacy_admin_notes()
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'bookings'
      AND COLUMN_NAME = 'admin_notes'
  ) THEN
    INSERT INTO booking_admin_notes (
      booking_id, admin_user_id, note, is_private, created_at
    )
    SELECT
      b.id,
      COALESCE(
        b.updated_by,
        b.created_by,
        (
          SELECT u.id
          FROM users u
          WHERE u.role IN ('ADMIN', 'SUPER_ADMIN')
            AND u.deleted_at IS NULL
          ORDER BY u.id
          LIMIT 1
        )
      ),
      b.admin_notes,
      1,
      COALESCE(b.updated_at, b.created_at)
    FROM bookings b
    WHERE b.admin_notes IS NOT NULL
      AND TRIM(b.admin_notes) <> ''
      AND COALESCE(
        b.updated_by,
        b.created_by,
        (
          SELECT u.id
          FROM users u
          WHERE u.role IN ('ADMIN', 'SUPER_ADMIN')
            AND u.deleted_at IS NULL
          ORDER BY u.id
          LIMIT 1
        )
      ) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM booking_admin_notes ban
        WHERE ban.booking_id = b.id
          AND ban.note = b.admin_notes
          AND ban.deleted_at IS NULL
      );

    ALTER TABLE bookings DROP COLUMN admin_notes;
  END IF;
END$$

DELIMITER ;

CALL sp_migrate_legacy_admin_notes();

DROP PROCEDURE IF EXISTS sp_migrate_legacy_admin_notes;

DROP TRIGGER IF EXISTS trg_bci_before_insert_validate;
DROP TRIGGER IF EXISTS trg_bci_before_update_validate;
DROP TRIGGER IF EXISTS trg_bci_after_insert_recalc_total;
DROP TRIGGER IF EXISTS trg_bci_after_update_recalc_total;
DROP TRIGGER IF EXISTS trg_bci_after_delete_recalc_total;
DROP TRIGGER IF EXISTS trg_bookings_total_amount_before_insert;
DROP TRIGGER IF EXISTS trg_bookings_total_amount_before_update;

DELIMITER $$

CREATE TRIGGER trg_bci_before_insert_validate
BEFORE INSERT ON booking_charge_items
FOR EACH ROW
BEGIN
  DECLARE v_policy_charge_type VARCHAR(50) DEFAULT NULL;

  IF ABS(NEW.amount - ROUND(NEW.quantity * NEW.unit_price, 2)) > 0.009 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'booking_charge_items.amount must equal quantity * unit_price';
  END IF;

  IF NEW.reference_type = 'CHARGE_POLICY' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CHARGE_POLICY reference requires reference_id';
    END IF;

    SELECT cp.charge_type INTO v_policy_charge_type
    FROM charge_policies cp
    WHERE cp.id = NEW.reference_id
      AND cp.deleted_at IS NULL
      AND cp.is_active = 1
    LIMIT 1;

    IF v_policy_charge_type IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive charge_policies reference_id';
    END IF;

    IF NEW.charge_type <> v_policy_charge_type THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'booking_charge_items.charge_type must match charge_policies.charge_type';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_bci_before_update_validate
BEFORE UPDATE ON booking_charge_items
FOR EACH ROW
BEGIN
  DECLARE v_policy_charge_type VARCHAR(50) DEFAULT NULL;

  IF ABS(NEW.amount - ROUND(NEW.quantity * NEW.unit_price, 2)) > 0.009 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'booking_charge_items.amount must equal quantity * unit_price';
  END IF;

  IF NEW.reference_type = 'CHARGE_POLICY' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CHARGE_POLICY reference requires reference_id';
    END IF;

    SELECT cp.charge_type INTO v_policy_charge_type
    FROM charge_policies cp
    WHERE cp.id = NEW.reference_id
      AND cp.deleted_at IS NULL
      AND cp.is_active = 1
    LIMIT 1;

    IF v_policy_charge_type IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive charge_policies reference_id';
    END IF;

    IF NEW.charge_type <> v_policy_charge_type THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'booking_charge_items.charge_type must match charge_policies.charge_type';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_bci_after_insert_recalc_total
AFTER INSERT ON booking_charge_items
FOR EACH ROW
BEGIN
  UPDATE bookings b
  SET b.total_amount = (
    SELECT COALESCE(SUM(bci.amount), 0.00)
    FROM booking_charge_items bci
    WHERE bci.booking_id = NEW.booking_id
      AND bci.deleted_at IS NULL
  )
  WHERE b.id = NEW.booking_id;
END$$

CREATE TRIGGER trg_bci_after_update_recalc_total
AFTER UPDATE ON booking_charge_items
FOR EACH ROW
BEGIN
  UPDATE bookings b
  SET b.total_amount = (
    SELECT COALESCE(SUM(bci.amount), 0.00)
    FROM booking_charge_items bci
    WHERE bci.booking_id = NEW.booking_id
      AND bci.deleted_at IS NULL
  )
  WHERE b.id = NEW.booking_id;

  IF OLD.booking_id <> NEW.booking_id THEN
    UPDATE bookings b
    SET b.total_amount = (
      SELECT COALESCE(SUM(bci.amount), 0.00)
      FROM booking_charge_items bci
      WHERE bci.booking_id = OLD.booking_id
        AND bci.deleted_at IS NULL
    )
    WHERE b.id = OLD.booking_id;
  END IF;
END$$

CREATE TRIGGER trg_bci_after_delete_recalc_total
AFTER DELETE ON booking_charge_items
FOR EACH ROW
BEGIN
  UPDATE bookings b
  SET b.total_amount = (
    SELECT COALESCE(SUM(bci.amount), 0.00)
    FROM booking_charge_items bci
    WHERE bci.booking_id = OLD.booking_id
      AND bci.deleted_at IS NULL
  )
  WHERE b.id = OLD.booking_id;
END$$

CREATE TRIGGER trg_bookings_total_amount_before_insert
BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
  IF NEW.total_amount <> 0.00 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'bookings.total_amount must be derived from booking_charge_items';
  END IF;
END$$

CREATE TRIGGER trg_bookings_total_amount_before_update
BEFORE UPDATE ON bookings
FOR EACH ROW
BEGIN
  DECLARE v_charge_total DECIMAL(12, 2) DEFAULT 0.00;

  IF NOT (NEW.total_amount <=> OLD.total_amount) THEN
    SELECT COALESCE(SUM(bci.amount), 0.00) INTO v_charge_total
    FROM booking_charge_items bci
    WHERE bci.booking_id = NEW.id
      AND bci.deleted_at IS NULL;

    IF NEW.total_amount <> v_charge_total THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'bookings.total_amount must equal SUM(booking_charge_items.amount)';
    END IF;
  END IF;
END$$

DELIMITER ;
