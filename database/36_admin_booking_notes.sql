-- Admin-only append-only booking notes.
-- The target database is selected by the migration runner; do not add USE here.

CREATE TABLE IF NOT EXISTS admin_booking_notes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  admin_user_id BIGINT UNSIGNED NOT NULL,
  note_text VARCHAR(1000) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_admin_booking_notes_booking_created (booking_id, created_at),
  CONSTRAINT fk_admin_booking_notes_booking
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_admin_booking_notes_admin_user
    FOREIGN KEY (admin_user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
