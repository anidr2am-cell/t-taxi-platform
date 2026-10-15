-- Apply only to isolated STG until production approval.
CREATE TABLE IF NOT EXISTS notification_email_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  delivery_id BIGINT UNSIGNED NOT NULL,
  trace_id CHAR(36) NOT NULL,
  message_id VARCHAR(255) NOT NULL,
  provider_message_id VARCHAR(255) NULL,
  envelope_encrypted MEDIUMTEXT NULL,
  outcome ENUM('SENDING','ACCEPTED','NOT_ACCEPTED','UNKNOWN') NOT NULL DEFAULT 'SENDING',
  error_code VARCHAR(80) NULL,
  smtp_command VARCHAR(30) NULL,
  smtp_response_code SMALLINT UNSIGNED NULL,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at DATETIME NULL,
  UNIQUE KEY uq_email_trace (trace_id),
  KEY idx_email_delivery (delivery_id,id),
  CONSTRAINT fk_email_attempt_delivery FOREIGN KEY (delivery_id) REFERENCES notification_deliveries(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notification_email_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  delivery_id BIGINT UNSIGNED NOT NULL,
  attempt_id BIGINT UNSIGNED NULL,
  action ENUM('RETRY_APPROVED','ACCEPTED_CONFIRMED','HANDLED_EXTERNALLY','KEEP_BLOCKED') NOT NULL,
  actor_user_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(1000) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_email_review_delivery (delivery_id,id),
  CONSTRAINT fk_email_review_delivery FOREIGN KEY (delivery_id) REFERENCES notification_deliveries(id) ON DELETE CASCADE,
  CONSTRAINT fk_email_review_attempt FOREIGN KEY (attempt_id) REFERENCES notification_email_attempts(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
