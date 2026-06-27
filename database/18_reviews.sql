-- TTaxi Platform — Customer reviews and ratings (Pack 15)
-- Depends on: 04_booking_core.sql (bookings, guest_access_tokens), 03_fleet_places.sql (drivers)

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  driver_id BIGINT UNSIGNED NOT NULL,
  customer_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  guest_access_token_id BIGINT UNSIGNED NULL DEFAULT NULL,
  rating TINYINT UNSIGNED NOT NULL,
  comment VARCHAR(500) NULL DEFAULT NULL,
  moderation_status ENUM('VISIBLE', 'HIDDEN') NOT NULL DEFAULT 'VISIBLE',
  hidden_reason VARCHAR(500) NULL DEFAULT NULL,
  reviewed_by BIGINT UNSIGNED NULL DEFAULT NULL,
  reviewed_at DATETIME NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_reviews_booking_id (booking_id),
  KEY idx_reviews_driver_status (driver_id, moderation_status, created_at),
  KEY idx_reviews_moderation_created (moderation_status, created_at),
  KEY idx_reviews_customer_user (customer_user_id),
  CONSTRAINT fk_reviews_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_reviews_driver_id
    FOREIGN KEY (driver_id) REFERENCES drivers (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_reviews_customer_user_id
    FOREIGN KEY (customer_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_reviews_guest_access_token_id
    FOREIGN KEY (guest_access_token_id) REFERENCES guest_access_tokens (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_reviews_reviewed_by
    FOREIGN KEY (reviewed_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_reviews_rating CHECK (rating >= 1 AND rating <= 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
