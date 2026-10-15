-- Export tracking/review records before rollback. Runtime must first use old code.
DROP TABLE IF EXISTS notification_email_reviews;
DROP TABLE IF EXISTS notification_email_attempts;
