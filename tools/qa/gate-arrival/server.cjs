// Isolated QA only. Never mount production data or credentials here.
const http=require('http'),crypto=require('crypto');
Object.assign(process.env,{NODE_ENV:'test',DB_HOST:'tride-gate-arrival-20261105-db',DB_USER:'root',DB_PASSWORD:'',DB_NAME:'gateqa',JWT_ACCESS_SECRET:crypto.randomBytes(24).toString('hex'),JWT_REFRESH_SECRET:crypto.randomBytes(24).toString('hex'),SOCIAL_TOKEN_ENCRYPTION_KEY:crypto.randomBytes(32).toString('hex')});
const {pool}=require('/qa/src/config/database');
const NotificationService=require('/qa/src/services/notification.service');
const NotificationRepository=require('/qa/src/repositories/notification.repository');
const Arrival=require('/qa/src/services/customerGateArrival.service');
const {formatInstantAsServiceDateTime}=require('/qa/src/utils/serviceDateTime.util');
const sql=[
 `CREATE TABLE IF NOT EXISTS qa_notification_devices(id BIGINT PRIMARY KEY,fcm_token TEXT,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)`,
 `CREATE TABLE IF NOT EXISTS bookings(id BIGINT PRIMARY KEY,booking_number VARCHAR(32),status VARCHAR(32),service_type_code VARCHAR(32),scheduled_pickup_at DATETIME)`,
 `CREATE TABLE IF NOT EXISTS booking_charge_items(id BIGINT PRIMARY KEY,booking_id BIGINT,charge_type VARCHAR(32),deleted_at DATETIME NULL)`,
 `CREATE TABLE IF NOT EXISTS drivers(id BIGINT PRIMARY KEY,user_id BIGINT,status VARCHAR(32),deleted_at DATETIME NULL)`,
 `CREATE TABLE IF NOT EXISTS booking_driver_assignments(id BIGINT PRIMARY KEY,booking_id BIGINT,driver_id BIGINT,is_active TINYINT,deleted_at DATETIME NULL)`,
 `CREATE TABLE IF NOT EXISTS notifications(id BIGINT AUTO_INCREMENT PRIMARY KEY,recipient_type VARCHAR(32),user_id BIGINT,recipient_driver_id BIGINT,booking_id BIGINT,audience_role VARCHAR(32),event_id VARCHAR(36),event_name VARCHAR(64),idempotency_key VARCHAR(191) UNIQUE,channel VARCHAR(32),type VARCHAR(64),title TEXT,body TEXT,payload JSON,status VARCHAR(32),read_at DATETIME NULL,created_at DATETIME DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,deleted_at DATETIME NULL)`,
 `CREATE TABLE IF NOT EXISTS notification_deliveries(id BIGINT AUTO_INCREMENT PRIMARY KEY,notification_id BIGINT,channel VARCHAR(32),delivery_status VARCHAR(32),attempt_count INT DEFAULT 0,last_error TEXT,delivered_at DATETIME NULL,created_at DATETIME DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)`
];
async function init(){for(const s of sql)await pool.query(s);await pool.query('INSERT IGNORE INTO bookings VALUES(1,?,?,?,?)',['TX209901010217','DRIVER_ASSIGNED','AIRPORT_PICKUP',formatInstantAsServiceDateTime(new Date())]);await pool.query("INSERT IGNORE INTO drivers VALUES(2,20,'ONLINE',NULL),(6,60,'ONLINE',NULL)");await pool.query('INSERT IGNORE INTO booking_driver_assignments VALUES(10,1,2,1,NULL)');}
const notifications=new NotificationService(pool,new NotificationRepository(pool),{}, {}, {}, {});
notifications.processDeliveries=async(id)=>{await pool.query("UPDATE notification_deliveries SET delivery_status=IF(channel='IN_APP','DELIVERED','SKIPPED'),last_error=IF(channel='FCM','QA_NO_LIVE_PUSH',last_error) WHERE notification_id=?",[id]);};
const service=new Arrival(pool,{
 findByBookingNumberForUpdate:async(conn,n)=>{const [r]=await conn.query('SELECT * FROM bookings WHERE booking_number=? FOR UPDATE',[n]);return r[0];},
 findTransferByBookingId:async()=>({airport_iata:'BKK'}),
},{assertCustomerOrGuestAccess:async(_,b,u,t)=>{if(t!=='qa-gate-arrival')throw Object.assign(Error('QA access denied'),{statusCode:403});}},notifications);
init().then(()=>http.createServer(async(req,res)=>{
 res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('X-Preview-Backend','tride-gate-arrival-20261105-backend');res.setHeader('Cache-Control','no-store');
 const url=new URL(req.url,'http://qa'),path=url.pathname;const reply=(code,data)=>{res.statusCode=code;res.end(JSON.stringify({success:code<400,data}));};
 try{
  if(path==='/api/v1/notifications/devices'&&req.method==='POST') {
    if(req.headers.authorization!=='Bearer qa-only')return reply(403,{qaOnly:true});
    let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>8192)return reply(413,{qaOnly:true});}
    const body=JSON.parse(raw);if(typeof body.token!=='string'||!body.token.length)return reply(422,{qaOnly:true});
    await pool.query('INSERT INTO qa_notification_devices(id,fcm_token) VALUES(1,?) ON DUPLICATE KEY UPDATE fcm_token=VALUES(fcm_token),updated_at=CURRENT_TIMESTAMP',[body.token]);
    return reply(200,{deviceId:1});
  }
  if(path==='/api/v1/health')return reply(200,{qaOnly:true});
  if(path==='/qa/reset'&&req.method==='POST'){await pool.query('DELETE FROM notification_deliveries');await pool.query('DELETE FROM notifications');return reply(200,{reset:true});}
  if(path==='/qa/inbox'){const rows=await notifications.notificationRepository.findNotifications({userId:20,recipientType:'USER',audienceRole:'DRIVER'},{limit:20,offset:0});return reply(200,{items:rows.map(row=>notifications.mapListItem(row))});}
  if(path==='/qa/db-check'){const [[n]]=await pool.query('SELECT COUNT(*) count FROM notifications');const [[a]]=await pool.query('SELECT driver_id driverId,is_active isActive FROM booking_driver_assignments WHERE id=10');const [[b]]=await pool.query('SELECT status FROM bookings WHERE id=1');const [deliveries]=await pool.query('SELECT channel,delivery_status status,last_error error FROM notification_deliveries');return reply(200,{notifications:n.count,assignment:a,booking:b,deliveries});}
  if(path==='/api/v1/bookings/TX209901010217/gate-arrival'&&['GET','POST'].includes(req.method))return reply(200,await service.run('TX209901010217',null,req.headers['x-guest-access-token'],req.method==='POST'));
  return reply(404,{qaOnly:true});
 }catch(e){return reply(e.statusCode||500,{error:e.errorCode||'QA_ERROR'});}
}).listen(3000)).catch(e=>{console.error(e.code||e.message);process.exit(1);});
