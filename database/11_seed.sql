-- TTaxi Platform — Seed data (MySQL 8)
-- Depends on: 00_database.sql through 10_views.sql
-- Idempotent inserts (safe re-run on empty rows).

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- service_categories
-- ---------------------------------------------------------------------------
INSERT INTO service_categories (code, name, sort_order, is_active)
SELECT 'TRANSFER', 'Airport Transfer', 1, 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM service_categories WHERE code = 'TRANSFER');

INSERT INTO service_categories (code, name, sort_order, is_active)
SELECT 'GOLF', 'Golf', 2, 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM service_categories WHERE code = 'GOLF');

-- ---------------------------------------------------------------------------
-- service_types
-- ---------------------------------------------------------------------------
INSERT INTO service_types (category_id, code, name, sort_order, is_active)
SELECT c.id, 'AIRPORT_PICKUP', 'Airport Pickup', 1, 1
FROM service_categories c
WHERE c.code = 'TRANSFER'
  AND NOT EXISTS (SELECT 1 FROM service_types WHERE code = 'AIRPORT_PICKUP');

INSERT INTO service_types (category_id, code, name, sort_order, is_active)
SELECT c.id, 'AIRPORT_DROPOFF', 'Airport Drop-off', 2, 1
FROM service_categories c
WHERE c.code = 'TRANSFER'
  AND NOT EXISTS (SELECT 1 FROM service_types WHERE code = 'AIRPORT_DROPOFF');

INSERT INTO service_types (category_id, code, name, sort_order, is_active)
SELECT c.id, 'CITY_TRANSFER', 'City Transfer', 3, 1
FROM service_categories c
WHERE c.code = 'TRANSFER'
  AND NOT EXISTS (SELECT 1 FROM service_types WHERE code = 'CITY_TRANSFER');

INSERT INTO service_types (category_id, code, name, sort_order, is_active)
SELECT c.id, 'GOLF_TRANSFER', 'Golf Transfer', 4, 1
FROM service_categories c
WHERE c.code = 'GOLF'
  AND NOT EXISTS (SELECT 1 FROM service_types WHERE code = 'GOLF_TRANSFER');

-- ---------------------------------------------------------------------------
-- vehicle_types
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'SEDAN', 'Sedan', 2, 2, 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'SEDAN');

INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'SUV', 'SUV', 3, 3, 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'SUV');

INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'VIP_SUV', 'VIP SUV', 3, 3, 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'VIP_SUV');

INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'VAN', 'Van', 8, 8, 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'VAN');

INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'VIP_VAN', 'VIP Van', 6, 6, 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'VIP_VAN');

INSERT INTO vehicle_types (code, name, max_passengers, max_luggage, sort_order, is_active)
SELECT 'LUXURY', 'Luxury', 3, 3, 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM vehicle_types WHERE code = 'LUXURY');

-- ---------------------------------------------------------------------------
-- vehicle_capacity_rules (PRD-aligned defaults)
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 2, 2, 0, 0, 1, 1, 1
FROM vehicle_types vt
WHERE vt.code = 'SEDAN'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 3, 2, 2, 1, 1, 5, 1
FROM vehicle_types vt
WHERE vt.code = 'SUV'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 3, 2, 2, 1, 1, 6, 1
FROM vehicle_types vt
WHERE vt.code = 'VIP_SUV'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 8, 8, 8, 4, 2, 10, 1
FROM vehicle_types vt
WHERE vt.code = 'VAN'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 6, 6, 6, 3, 2, 9, 1
FROM vehicle_types vt
WHERE vt.code = 'VIP_VAN'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

INSERT INTO vehicle_capacity_rules (
  vehicle_type_id, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage, priority, is_active
)
SELECT vt.id, 3, 2, 2, 1, 1, 7, 1
FROM vehicle_types vt
WHERE vt.code = 'LUXURY'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_capacity_rules vcr WHERE vcr.vehicle_type_id = vt.id
  );

-- ---------------------------------------------------------------------------
-- vehicle_prices (fallback THB base prices — adjust in admin)
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_prices (service_type_id, vehicle_type_id, base_price, currency, is_active)
SELECT st.id, vt.id, 800.00, 'THB', 1
FROM service_types st, vehicle_types vt
WHERE st.code = 'AIRPORT_PICKUP' AND vt.code = 'SEDAN'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_prices vp
    WHERE vp.service_type_id = st.id AND vp.vehicle_type_id = vt.id AND vp.region_code IS NULL
  );

INSERT INTO vehicle_prices (service_type_id, vehicle_type_id, base_price, currency, is_active)
SELECT st.id, vt.id, 1000.00, 'THB', 1
FROM service_types st, vehicle_types vt
WHERE st.code = 'AIRPORT_PICKUP' AND vt.code = 'SUV'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_prices vp
    WHERE vp.service_type_id = st.id AND vp.vehicle_type_id = vt.id AND vp.region_code IS NULL
  );

INSERT INTO vehicle_prices (service_type_id, vehicle_type_id, base_price, currency, is_active)
SELECT st.id, vt.id, 1500.00, 'THB', 1
FROM service_types st, vehicle_types vt
WHERE st.code = 'AIRPORT_PICKUP' AND vt.code = 'VAN'
  AND NOT EXISTS (
    SELECT 1 FROM vehicle_prices vp
    WHERE vp.service_type_id = st.id AND vp.vehicle_type_id = vt.id AND vp.region_code IS NULL
  );

-- ---------------------------------------------------------------------------
-- airports (Thailand major)
-- ---------------------------------------------------------------------------
INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active)
SELECT 'BKK', 'VTBS', 'TH', 'Bangkok', 'Suvarnabhumi Airport', 'Asia/Bangkok', 1
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM airports WHERE iata_code = 'BKK');

INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active)
SELECT 'DMK', 'VTBD', 'TH', 'Bangkok', 'Don Mueang International Airport', 'Asia/Bangkok', 1
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM airports WHERE iata_code = 'DMK');

INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active)
SELECT 'CNX', 'VTCC', 'TH', 'Chiang Mai', 'Chiang Mai International Airport', 'Asia/Bangkok', 1
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM airports WHERE iata_code = 'CNX');

INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active)
SELECT 'HKT', 'VTSP', 'TH', 'Phuket', 'Phuket International Airport', 'Asia/Bangkok', 1
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM airports WHERE iata_code = 'HKT');

-- ---------------------------------------------------------------------------
-- settings (defaults)
-- ---------------------------------------------------------------------------
INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'general', 'company_name', 'TTaxi', 'STRING', 0, 'Company display name'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'general' AND key_name = 'company_name'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'general', 'support_email', 'support@ttaxi.example', 'STRING', 0, 'Support email'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'general' AND key_name = 'support_email'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'pricing', 'name_sign_price', '100', 'NUMBER', 0, 'Name sign service price (THB)'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'pricing' AND key_name = 'name_sign_price'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'booking', 'guest_token_ttl_days', '90', 'NUMBER', 0, 'Guest access token TTL (days)'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'booking' AND key_name = 'guest_token_ttl_days'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'dispatch', 'delay_threshold_minutes', '15', 'NUMBER', 0, 'Flight delay alert threshold'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'dispatch' AND key_name = 'delay_threshold_minutes'
);

INSERT INTO settings (group_name, key_name, value, data_type, is_encrypted, description)
SELECT 'vehicle', 'multi_assign_strategy', 'GREEDY_PRIORITY', 'STRING', 0, 'Multi-vehicle assignment strategy'
FROM DUAL WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE group_name = 'vehicle' AND key_name = 'multi_assign_strategy'
);
