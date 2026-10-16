-- Deactivate only. Preserve courses referenced by existing bookings and historical amounts.
START TRANSACTION;
UPDATE golf_courses g JOIN golf_course_catalog c ON c.golf_course_id=g.id SET g.is_active=0;
UPDATE golf_group_prices SET is_active=0;
INSERT INTO audit_logs(user_id,action,entity_type,payload) VALUES(NULL,'GOLF_CATALOG_DISABLED','golf',JSON_OBJECT('migration',76,'reason','approved rollback'));
COMMIT;
