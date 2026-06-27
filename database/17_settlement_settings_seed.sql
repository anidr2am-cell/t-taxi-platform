-- TTaxi Platform — Settlement configuration seed (no schema changes)
-- Depends on: 08_platform.sql (settings table)

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'settlement', 'commission_rate_percent', '10', 'NUMBER', 0, 'Platform commission percent of booking total amount'
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'settlement' AND key_name = 'commission_rate_percent'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'settlement', 'commission_due_days', '7', 'NUMBER', 0, 'Days after trip completion before commission is due'
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'settlement' AND key_name = 'commission_due_days'
);
