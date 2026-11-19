-- Refuse enum rollback while any Telegram connection history exists. Do not
-- delete history or convert channels. In that case roll back code only.
DELIMITER $$
DROP PROCEDURE IF EXISTS rollback_78_customer_messengers$$
CREATE PROCEDURE rollback_78_customer_messengers()
BEGIN
 IF EXISTS(SELECT 1 FROM booking_contact_connections WHERE channel='TELEGRAM') THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Telegram history exists: code-only rollback required';
 END IF;
 START TRANSACTION;
 DELETE s FROM settings s LEFT JOIN migration_78_contact_settings_backup b
 ON b.group_name=s.group_name AND b.key_name=s.key_name
 WHERE b.id IS NULL AND s.group_name='contact_channels'
 AND s.key_name IN ('contactWechatEnabled','contactTelegramEnabled','contactTelegramDisplayName','contactTelegramAddUrl');
 UPDATE settings s JOIN migration_78_contact_settings_backup b ON s.id=b.id
 SET s.value=b.value,s.data_type=b.data_type,s.deleted_at=b.deleted_at,
 s.updated_at=b.updated_at,s.updated_by=b.updated_by,s.updated_by_user_id=b.updated_by_user_id;
 COMMIT;
 ALTER TABLE booking_contact_connections MODIFY COLUMN channel
 ENUM('LINE','KAKAO','WHATSAPP','WECHAT','EMAIL') NOT NULL;
END$$
CALL rollback_78_customer_messengers()$$
DROP PROCEDURE rollback_78_customer_messengers$$
DELIMITER ;
