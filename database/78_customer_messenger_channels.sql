-- No booking, payment, assignment or email delivery rows are changed.
-- Add Telegram to connection history and enable the owner-supplied channels.
CREATE TABLE IF NOT EXISTS migration_78_contact_settings_backup AS
 SELECT * FROM settings WHERE
 (group_name='contact_channels' AND key_name IN ('contactWechatEnabled','contactTelegramEnabled','contactTelegramDisplayName','contactTelegramAddUrl'))
 OR (group_name='operations' AND key_name='contactWechatQrImagePath');

ALTER TABLE booking_contact_connections MODIFY COLUMN channel
 ENUM('LINE','KAKAO','WHATSAPP','WECHAT','EMAIL','TELEGRAM') NOT NULL;

START TRANSACTION;
INSERT INTO settings(group_name,key_name,value,data_type) VALUES
 ('contact_channels','contactWechatEnabled','true','STRING'),
 ('contact_channels','contactTelegramEnabled','true','STRING'),
 ('contact_channels','contactTelegramDisplayName','Telegram','STRING'),
 ('contact_channels','contactTelegramAddUrl','https://t.me/TRider_taxi','STRING')
 ON DUPLICATE KEY UPDATE value=VALUES(value),deleted_at=NULL;
-- Empty path deliberately selects the bundled, unmodified 21718.jpg QR.
UPDATE settings SET value='' WHERE group_name='operations' AND key_name='contactWechatQrImagePath';
COMMIT;
