CREATE DATABASE IF NOT EXISTS ttaxi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ttaxi;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  country VARCHAR(100),
  role ENUM('customer', 'driver', 'admin') DEFAULT 'customer',
  fcm_token VARCHAR(512),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS airports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(10) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  city VARCHAR(100),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vehicles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN') NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  max_passengers INT NOT NULL,
  max_luggage INT NOT NULL,
  is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS vehicle_prices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  vehicle_type ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN') NOT NULL,
  service_type ENUM('airport_pickup', 'airport_dropoff', 'city_transfer', 'golf_transfer') NOT NULL,
  base_price DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'THB',
  is_active BOOLEAN DEFAULT TRUE,
  UNIQUE KEY uk_vehicle_service (vehicle_type, service_type)
);

CREATE TABLE IF NOT EXISTS golf_courses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  region ENUM('Bangkok', 'Pattaya', 'Chiang Mai', 'Hua Hin', 'Phuket', 'Khao Yai', 'Chiang Rai', 'Kanchanaburi') NOT NULL,
  place_id VARCHAR(255),
  address TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS drivers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50) NOT NULL,
  license_number VARCHAR(100),
  vehicle_type ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN'),
  is_available BOOLEAN DEFAULT TRUE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS reservations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  reservation_number VARCHAR(20) NOT NULL UNIQUE,
  user_id INT,
  service_type ENUM('airport_pickup', 'airport_dropoff', 'city_transfer', 'golf_transfer') NOT NULL,
  status ENUM('pending', 'confirmed', 'driver_assigned', 'completed', 'cancelled') DEFAULT 'pending',
  origin_place_id VARCHAR(255),
  origin_address TEXT,
  destination_place_id VARCHAR(255),
  destination_address TEXT,
  airport_code VARCHAR(10),
  flight_number VARCHAR(20),
  flight_scheduled_arrival DATETIME,
  flight_estimated_arrival DATETIME,
  flight_delay_status VARCHAR(50),
  flight_data JSON,
  pickup_date DATE,
  pickup_time TIME,
  golf_region VARCHAR(50),
  golf_course_id INT,
  driver_included BOOLEAN DEFAULT FALSE,
  recommended_vehicle_type ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN'),
  selected_vehicle_type ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN') NOT NULL,
  vehicle_count INT DEFAULT 1,
  vehicle_assignment JSON,
  name_sign_service BOOLEAN DEFAULT FALSE,
  name_sign_price DECIMAL(10, 2) DEFAULT 0,
  base_price DECIMAL(10, 2) NOT NULL,
  total_price DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'THB',
  special_requests TEXT,
  customer_name VARCHAR(255),
  customer_email VARCHAR(255),
  customer_phone VARCHAR(50),
  customer_country VARCHAR(100),
  driver_id INT,
  admin_price_override DECIMAL(10, 2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (golf_course_id) REFERENCES golf_courses(id) ON DELETE SET NULL,
  FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS reservation_passengers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  reservation_id INT NOT NULL,
  adults INT DEFAULT 0,
  children INT DEFAULT 0,
  FOREIGN KEY (reservation_id) REFERENCES reservations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS reservation_luggage (
  id INT AUTO_INCREMENT PRIMARY KEY,
  reservation_id INT NOT NULL,
  small_carriers INT DEFAULT 0,
  large_carriers INT DEFAULT 0,
  golf_bags INT DEFAULT 0,
  special_items TEXT,
  FOREIGN KEY (reservation_id) REFERENCES reservations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chat_rooms (
  id INT AUTO_INCREMENT PRIMARY KEY,
  room_id VARCHAR(50) NOT NULL UNIQUE,
  reservation_id INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (reservation_id) REFERENCES reservations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  room_id VARCHAR(50) NOT NULL,
  sender_id INT,
  sender_role ENUM('customer', 'driver', 'admin') NOT NULL,
  sender_name VARCHAR(255),
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_room_created (room_id, created_at)
);

CREATE TABLE IF NOT EXISTS notifications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  reservation_id INT,
  type VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  body TEXT,
  is_read BOOLEAN DEFAULT FALSE,
  fcm_sent BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (reservation_id) REFERENCES reservations(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS settings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  key_name VARCHAR(100) NOT NULL UNIQUE,
  value TEXT,
  description VARCHAR(255),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS translations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  key_name VARCHAR(100) NOT NULL,
  language ENUM('en', 'ko', 'zh', 'ja', 'th') NOT NULL,
  value TEXT NOT NULL,
  UNIQUE KEY uk_key_lang (key_name, language)
);

-- Seed data
INSERT INTO airports (code, name, city) VALUES
  ('BKK', 'Suvarnabhumi Airport', 'Bangkok'),
  ('DMK', 'Don Mueang Airport', 'Bangkok'),
  ('HKT', 'Phuket Airport', 'Phuket'),
  ('CNX', 'Chiang Mai Airport', 'Chiang Mai'),
  ('UTP', 'U-Tapao Airport', 'Pattaya'),
  ('KBV', 'Krabi Airport', 'Krabi');

INSERT INTO vehicles (type, name, max_passengers, max_luggage) VALUES
  ('SEDAN', 'Sedan', 2, 4),
  ('SUV', 'SUV', 3, 4),
  ('VIP_SUV', 'VIP SUV', 3, 4),
  ('VAN', 'Van', 8, 8);

INSERT INTO vehicle_prices (vehicle_type, service_type, base_price) VALUES
  ('SEDAN', 'airport_pickup', 1200),
  ('SUV', 'airport_pickup', 1500),
  ('VIP_SUV', 'airport_pickup', 2000),
  ('VAN', 'airport_pickup', 2000),
  ('SEDAN', 'airport_dropoff', 1200),
  ('SUV', 'airport_dropoff', 1500),
  ('VIP_SUV', 'airport_dropoff', 2000),
  ('VAN', 'airport_dropoff', 2000),
  ('SEDAN', 'city_transfer', 1000),
  ('SUV', 'city_transfer', 1300),
  ('VIP_SUV', 'city_transfer', 1800),
  ('VAN', 'city_transfer', 1800),
  ('SEDAN', 'golf_transfer', 1500),
  ('SUV', 'golf_transfer', 1800),
  ('VIP_SUV', 'golf_transfer', 2200),
  ('VAN', 'golf_transfer', 2200);

INSERT INTO golf_courses (name, region) VALUES
  ('Siam Country Club', 'Pattaya'),
  ('Laem Chabang', 'Pattaya'),
  ('Chee Chan Golf Resort', 'Pattaya'),
  ('Phoenix Gold Golf & Country Club', 'Pattaya'),
  ('Thai Country Club', 'Bangkok'),
  ('Alpine Golf Club', 'Bangkok'),
  ('Chiang Mai Highlands Golf', 'Chiang Mai'),
  ('Black Mountain Golf Club', 'Hua Hin');

INSERT INTO settings (key_name, value, description) VALUES
  ('name_sign_price', '100', 'Name sign service price in THB'),
  ('company_name', 'TTaxi', 'Company name'),
  ('support_email', 'support@ttaxi.com', 'Support email'),
  ('support_phone', '+66-2-123-4567', 'Support phone');

INSERT INTO users (email, name, role) VALUES
  ('admin@ttaxi.com', 'Admin', 'admin');
