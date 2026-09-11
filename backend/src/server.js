import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import pg from 'pg';
import crypto from 'crypto';
import fs from 'fs';
import { WebSocketServer } from 'ws';
import { AccessToken } from 'livekit-server-sdk';

const { Pool } = pg;
const app = express();
app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
const allowedOrigins = String(process.env.CORS_ORIGINS || '').split(',').map(x=>x.trim()).filter(Boolean);
app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : false, credentials: false }));
app.use(express.json({ limit: '256kb', strict: true }));
app.disable('x-powered-by');
app.use((req,res,next)=>{ res.setHeader('X-Content-Type-Options','nosniff'); res.setHeader('Referrer-Policy','no-referrer'); next(); });
const rateBuckets = new Map();
function rateLimit(key, limit, windowMs) {
  const now=Date.now(); const b=rateBuckets.get(key);
  if(!b || now-b.start>=windowMs){ rateBuckets.set(key,{start:now,count:1}); return true; }
  if(b.count>=limit) return false; b.count++; return true;
}
setInterval(()=>{ const cutoff=Date.now()-15*60*1000; for(const [k,v] of rateBuckets) if(v.start<cutoff) rateBuckets.delete(k); }, 5*60*1000).unref();
app.use((req,res,next)=>{ if(req.path==='/health') return next(); const ip=req.ip||req.socket.remoteAddress||'unknown'; if(!rateLimit(`ip:${ip}`,180,60*1000)) return res.status(429).json({error:'RATE_LIMITED'}); next(); });
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const PORT = Number(process.env.PORT || 8080);
const SECRET = String(process.env.JWT_SECRET || '');
if (!SECRET || SECRET.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');
if (process.env.NODE_ENV === 'production') {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required in production');
  if (!process.env.CORS_ORIGINS) throw new Error('CORS_ORIGINS is required in production');
  if (!process.env.LIVEKIT_URL || !/^wss:\/\//.test(process.env.LIVEKIT_URL)) throw new Error('LIVEKIT_URL must use wss:// in production');
  if (!process.env.LIVEKIT_API_KEY || !process.env.LIVEKIT_API_SECRET) throw new Error('LiveKit credentials are required in production');
  if (process.env.OTP_DEV_MODE === 'true' || process.env.ALLOW_TEST_BILLING === 'true') throw new Error('Development billing/OTP flags must be disabled in production');
}
const sockets = new Map(); // roomCode -> Set<WebSocket>

async function db(sql, params=[]) { return pool.query(sql, params); }
function token(user) { return jwt.sign({ sub: user.id, publicId: user.public_id }, SECRET, { expiresIn: '30d' }); }
function auth(req,res,next) {
  try { const h=req.headers.authorization||''; req.user=jwt.verify(h.replace(/^Bearer\s+/i,''),SECRET); next(); }
  catch { res.status(401).json({error:'UNAUTHORIZED'}); }
}
function publicId(){ return 'LS' + crypto.randomInt(10000000,99999999); }

app.get('/health', async (_req,res)=>{ try { await db('SELECT 1'); res.json({ok:true,version:'2.7.0',environment:process.env.NODE_ENV||'development'}); } catch(e){res.status(503).json({ok:false});} });
app.get('/ready', async (_req,res)=>{ try { await db('SELECT 1'); if(process.env.NODE_ENV==='production' && (!process.env.LIVEKIT_URL || !process.env.LIVEKIT_API_KEY || !process.env.LIVEKIT_API_SECRET)) return res.status(503).json({ok:false,error:'LIVEKIT_NOT_CONFIGURED'}); res.json({ok:true}); } catch(e){ res.status(503).json({ok:false,error:'DATABASE_UNAVAILABLE'}); } });

app.post('/auth/request-otp', async (req,res)=>{
  const phoneKey=String(req.body.phone||'').trim();
  const ip=req.ip||req.socket.remoteAddress||'unknown';
  if(!rateLimit(`otp:${phoneKey}`,5,15*60*1000) || !rateLimit(`otp-ip:${ip}`,20,15*60*1000)) return res.status(429).json({error:'OTP_RATE_LIMITED'});
  const phone=String(req.body.phone||'').trim(); if(!/^\+964\d{8,10}$/.test(phone)) return res.status(400).json({error:'INVALID_PHONE'});
  const code=String(crypto.randomInt(100000,1000000));
  const hash=await bcrypt.hash(code,10);
  await db('INSERT INTO otp_codes(phone,code_hash,expires_at) VALUES($1,$2,now()+interval \'5 minutes\')',[phone,hash]);
  // Production: send code through an approved SMS provider. Never expose OTP in production.
  res.json({ok:true, ...(process.env.OTP_DEV_MODE==='true' ? {devCode:code} : {})});
});

app.post('/auth/verify-otp', async (req,res)=>{
  const phone=String(req.body.phone||'').trim(), code=String(req.body.code||'').trim();
  if(!/^\+964\d{8,10}$/.test(phone) || !/^\d{6}$/.test(code)) return res.status(400).json({error:'INVALID_OTP'});
  const ip=req.ip||req.socket.remoteAddress||'unknown';
  if(!rateLimit(`verify:${phone}:${ip}`,8,15*60*1000)) return res.status(429).json({error:'OTP_VERIFY_RATE_LIMITED'});
  const r=await db('SELECT * FROM otp_codes WHERE phone=$1 AND used=false AND expires_at>now() ORDER BY id DESC LIMIT 1',[phone]);
  if(!r.rows[0] || !(await bcrypt.compare(code,r.rows[0].code_hash))) return res.status(401).json({error:'INVALID_OTP'});
  await db('UPDATE otp_codes SET used=true WHERE id=$1',[r.rows[0].id]);
  let u=(await db('SELECT * FROM users WHERE phone=$1',[phone])).rows[0];
  if(!u){
    for(let i=0;i<10;i++){ try { u=(await db('INSERT INTO users(public_id,phone) VALUES($1,$2) RETURNING *',[publicId(),phone])).rows[0]; break; } catch(e){} }
  }
  res.json({token:token(u), user:{id:u.public_id,displayName:u.display_name,coins:u.coins,xp:u.xp,vipLevel:u.vip_level}});
});

async function applyVipDecay(userId){
  const r=await db('SELECT vip_level,vip_expires_at,vip_decay_at FROM users WHERE id=$1',[userId]);
  const u=r.rows[0]; if(!u || !u.vip_level || !u.vip_expires_at) return u;
  const now=new Date(); const exp=new Date(u.vip_expires_at);
  if(now <= exp) return u;
  let decayAt=u.vip_decay_at ? new Date(u.vip_decay_at) : exp;
  let level=Number(u.vip_level);
  while(level>1 && now >= new Date(decayAt.getTime()+30*24*60*60*1000)) { level--; decayAt=new Date(decayAt.getTime()+30*24*60*60*1000); }
  if(level!==Number(u.vip_level)) await db('UPDATE users SET vip_level=$1,vip_decay_at=$2 WHERE id=$3',[level,decayAt,userId]);
  return {...u,vip_level:level,vip_decay_at:decayAt};
}

app.get('/me',auth,async(req,res)=>{ await applyVipDecay(req.user.sub); const r=await db(`SELECT public_id,display_name,avatar_url,coins,diamonds,xp,vip_level,vip_expires_at,vip_decay_at FROM users WHERE id=$1`,[req.user.sub]); const u=r.rows[0]; if(!u) return res.json(null); res.json({...u,vipLevel:u.vip_level, vipExpiresAt:u.vip_expires_at, vipDaysRemaining:u.vip_expires_at?Math.max(0,Math.ceil((new Date(u.vip_expires_at)-Date.now())/86400000)):0, animatedProfile:u.vip_level>=7, profileFrame:u.vip_level>=7, nameBubble:u.vip_level>=7, entranceEffect:u.vip_level>=7}); });

app.get('/vip/status',auth,async(req,res)=>{ await applyVipDecay(req.user.sub); const r=await db('SELECT vip_level,xp,vip_expires_at,vip_decay_at FROM users WHERE id=$1',[req.user.sub]); const u=r.rows[0]; const level=Number(u?.vip_level||0); res.json({level,xp:Number(u?.xp||0),expiresAt:u?.vip_expires_at||null,daysRemaining:u?.vip_expires_at?Math.max(0,Math.ceil((new Date(u.vip_expires_at)-Date.now())/86400000)):0,animatedProfile:level>=7,frame:level>=7,nameBubble:level>=7,entranceEffect:level>=7,maxLevel:30}); });

app.post('/vip/renew',auth,async(req,res)=>{ if(process.env.ALLOW_TEST_BILLING !== 'true') return res.status(404).json({error:'NOT_FOUND'}); const requested=Math.max(1,Math.min(30,Number(req.body.level)||Number((await db('SELECT vip_level FROM users WHERE id=$1',[req.user.sub])).rows[0]?.vip_level||1))); const r=await db(`UPDATE users SET vip_level=$1,vip_started_at=now(),vip_expires_at=now()+interval '30 days',vip_decay_at=now() WHERE id=$2 RETURNING vip_level,vip_expires_at`,[requested,req.user.sub]); res.json({level:r.rows[0].vip_level,expiresAt:r.rows[0].vip_expires_at,daysRemaining:30}); });

app.get('/chat/stickers',auth,async(req,res)=>{ const r=await db('SELECT id,code,name,visual,vip_required AS "vipRequired" FROM animated_stickers WHERE active=true ORDER BY vip_required,id'); res.json(r.rows); });
app.get('/wallet/packages',auth,async(req,res)=>{ const r=await db('SELECT id,coins,price_usd AS "priceUsd",diamond_bonus AS "diamondBonus" FROM coin_packages WHERE active=true ORDER BY price_usd'); res.json(r.rows.map(x=>({...x,coins:Number(x.coins),priceUsd:Number(x.priceUsd),diamondBonus:Number(x.diamondBonus||0)}))); });
app.post('/payments/orders',auth,async(req,res)=>{ const packageId=Number(req.body.packageId); const method=String(req.body.method||''); if(!Number.isInteger(packageId)||!['card','google_pay','apple_pay','asiacell'].includes(method)) return res.status(400).json({error:'INVALID_PAYMENT'}); const p=(await db('SELECT id,coins,price_usd,diamond_bonus FROM coin_packages WHERE id=$1 AND active=true',[packageId])).rows[0]; if(!p) return res.status(404).json({error:'PACKAGE_NOT_FOUND'}); const id=crypto.randomUUID(); await db('INSERT INTO payment_orders(id,user_id,package_id,method) VALUES($1,$2,$3,$4)',[id,req.user.sub,p.id,method]); res.json({orderId:id,status:'pending',coins:Number(p.coins),priceUsd:Number(p.price_usd),diamondBonus:Number(p.diamond_bonus||0),method, message:'بانتظار تأكيد بوابة الدفع'}); });
app.get('/payments/orders/:id',auth,async(req,res)=>{ const r=(await db(`SELECT o.id,o.status,o.method,o.provider_reference AS "providerReference",p.coins,p.price_usd AS "priceUsd",o.created_at AS "createdAt",o.paid_at AS "paidAt" FROM payment_orders o JOIN coin_packages p ON p.id=o.package_id WHERE o.id=$1 AND o.user_id=$2`,[req.params.id,req.user.sub])).rows[0]; if(!r) return res.status(404).json({error:'ORDER_NOT_FOUND'}); res.json({...r,coins:Number(r.coins),priceUsd:Number(r.priceUsd)}); });

app.get('/wallet/diamonds',auth,async(req,res)=>{ const r=(await db('SELECT diamonds,active_frame_code FROM users WHERE id=$1',[req.user.sub])).rows[0]||{}; res.json({diamonds:Number(r.diamonds||0),activeFrameCode:r.active_frame_code||null}); });
app.get('/wallet/diamond-store',auth,async(req,res)=>{ const r=await db('SELECT id,code,name,item_type AS "itemType",price_diamonds AS "priceDiamonds" FROM diamond_store_items WHERE active=true ORDER BY price_diamonds'); res.json(r.rows.map(x=>({...x,priceDiamonds:Number(x.priceDiamonds)}))); });
app.post('/wallet/diamond-store/purchase',auth,async(req,res)=>{ const code=String(req.body.code||'').trim(); if(!code) return res.status(400).json({error:'INVALID_ITEM'}); const client=await pool.connect(); try{ await client.query('BEGIN'); const item=(await client.query('SELECT id,code,name,item_type,price_diamonds FROM diamond_store_items WHERE code=$1 AND active=true',[code])).rows[0]; const u=(await client.query('SELECT diamonds FROM users WHERE id=$1 FOR UPDATE',[req.user.sub])).rows[0]; if(!item||!u||Number(u.diamonds)<Number(item.price_diamonds)) throw new Error('INSUFFICIENT_DIAMONDS'); await client.query('UPDATE users SET diamonds=diamonds-$1 WHERE id=$2',[item.price_diamonds,req.user.sub]); if(item.item_type==='frame') await client.query('UPDATE users SET active_frame_code=$1 WHERE id=$2',[item.code,req.user.sub]); await client.query(`INSERT INTO transactions(user_id,type,coins,reference,metadata) VALUES($1,'diamond_store',0,$2,$3)`,[req.user.sub,item.code,JSON.stringify({itemType:item.item_type,diamonds:Number(item.price_diamonds)})]); await client.query('COMMIT'); res.json({ok:true,remainingDiamonds:Number(u.diamonds)-Number(item.price_diamonds),item:item.name}); }catch(e){await client.query('ROLLBACK');res.status(400).json({error:'DIAMOND_PURCHASE_FAILED'});}finally{client.release();} });

app.get('/transactions',auth,async(req,res)=>{ const r=await db('SELECT id,type,coins,amount_usd,reference,metadata,created_at FROM transactions WHERE user_id=$1 ORDER BY id DESC LIMIT 100',[req.user.sub]); res.json(r.rows); });

app.get('/users/:publicId/social',auth,async(req,res)=>{
  const u=(await db('SELECT id,public_id,display_name,avatar_url,xp,vip_level FROM users WHERE public_id=$1',[req.params.publicId])).rows[0];
  if(!u) return res.status(404).json({error:'USER_NOT_FOUND'});
  const counts=(await db(`SELECT (SELECT count(*) FROM follows WHERE following_id=$1) followers,(SELECT count(*) FROM follows WHERE follower_id=$1) following`,[u.id])).rows[0];
  const following=(await db('SELECT 1 FROM follows WHERE follower_id=$1 AND following_id=$2',[req.user.sub,u.id])).rowCount>0;
  res.json({id:u.public_id,name:u.display_name,avatar:u.avatar_url,xp:Number(u.xp),vipLevel:u.vip_level,followers:Number(counts.followers),following:Number(counts.following),isFollowing:following});
});
app.post('/users/:publicId/follow',auth,async(req,res)=>{
  const target=(await db('SELECT id,public_id FROM users WHERE public_id=$1',[req.params.publicId])).rows[0];
  if(!target || target.id===req.user.sub) return res.status(400).json({error:'INVALID_TARGET'});
  await db('INSERT INTO follows(follower_id,following_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[req.user.sub,target.id]);
  const n=(await db('SELECT count(*) FROM follows WHERE following_id=$1',[target.id])).rows[0].count;
  res.json({following:true,followers:Number(n)});
});
app.delete('/users/:publicId/follow',auth,async(req,res)=>{
  const target=(await db('SELECT id FROM users WHERE public_id=$1',[req.params.publicId])).rows[0];
  if(!target) return res.status(404).json({error:'USER_NOT_FOUND'});
  await db('DELETE FROM follows WHERE follower_id=$1 AND following_id=$2',[req.user.sub,target.id]);
  const n=(await db('SELECT count(*) FROM follows WHERE following_id=$1',[target.id])).rows[0].count;
  res.json({following:false,followers:Number(n)});
});
app.get('/leaderboard/users',auth,async(req,res)=>{
  const r=await db(`SELECT public_id AS id,display_name AS name,xp,coins,vip_level AS "vipLevel",(SELECT count(*) FROM follows f WHERE f.following_id=u.id) AS followers
    FROM users u ORDER BY xp DESC, followers DESC, id LIMIT 50`);
  res.json(r.rows.map(x=>({...x,xp:Number(x.xp),coins:Number(x.coins),followers:Number(x.followers)})));
});
app.get('/rooms/:roomId/stats',auth,async(req,res)=>{
  const room=(await db('SELECT id FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0]; if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  await db('INSERT INTO room_stats(room_id) VALUES($1) ON CONFLICT DO NOTHING',[room.id]);
  const r=(await db('SELECT likes,gifts_coins FROM room_stats WHERE room_id=$1',[room.id])).rows[0]; res.json({likes:Number(r.likes),giftsCoins:Number(r.gifts_coins)});
});
app.post('/rooms/:roomId/like',auth,async(req,res)=>{
  const room=(await db('SELECT id FROM rooms WHERE room_code=$1 AND is_live=true',[req.params.roomId])).rows[0]; if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  const client=await pool.connect(); try { await client.query('BEGIN'); const added=(await client.query('INSERT INTO room_likes(room_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING user_id',[room.id,req.user.sub])).rowCount; await client.query('INSERT INTO room_stats(room_id,likes) VALUES($1,$2) ON CONFLICT(room_id) DO UPDATE SET likes=room_stats.likes+$2,updated_at=now()',[room.id,added]); const r=(await client.query('SELECT likes FROM room_stats WHERE room_id=$1',[room.id])).rows[0]; await client.query('COMMIT'); broadcast(req.params.roomId,{type:'like_count',count:Number(r.likes)}); res.json({liked:added>0,likes:Number(r.likes)}); } catch(e){await client.query('ROLLBACK');res.status(500).json({error:'LIKE_FAILED'});} finally{client.release();}
});

app.post('/wallet/credit',auth,async(req,res)=>{
  if(process.env.ALLOW_TEST_BILLING !== 'true') return res.status(404).json({error:'NOT_FOUND'});
  const coins=Number(req.body.coins); if(!Number.isSafeInteger(coins)||coins<=0) return res.status(400).json({error:'INVALID_COINS'});
  const client=await pool.connect();
  try{ await client.query('BEGIN'); const u=(await client.query('UPDATE users SET coins=coins+$1 WHERE id=$2 RETURNING coins',[coins,req.user.sub])).rows[0]; await client.query('INSERT INTO transactions(user_id,type,coins,reference) VALUES($1,\'credit_test\',$2,$3)',[req.user.sub,coins,String(req.body.reference||'test')]); await client.query('COMMIT'); res.json({coins:u.coins}); } catch(e){await client.query('ROLLBACK');res.status(500).json({error:'FAILED'});} finally{client.release();}
});

app.post('/wallet/transfer',auth,async(req,res)=>{
  const to=String(req.body.toPublicId||'').trim(), coins=Number(req.body.coins);
  if(!to || !Number.isSafeInteger(coins)||coins<10) return res.status(400).json({error:'INVALID_TRANSFER'});
  const client=await pool.connect();
  try{
    await client.query('BEGIN');
    const from=(await client.query('SELECT id,coins FROM users WHERE id=$1 FOR UPDATE',[req.user.sub])).rows[0];
    const target=(await client.query('SELECT id FROM users WHERE public_id=$1 FOR UPDATE',[to])).rows[0];
    if(!from||!target||from.id===target.id||from.coins<coins) throw new Error('INSUFFICIENT_OR_INVALID');
    await client.query('UPDATE users SET coins=coins-$1 WHERE id=$2',[coins,from.id]);
    await client.query('UPDATE users SET coins=coins+$1,xp=xp+$2 WHERE id=$3',[coins,Math.floor(coins/10),target.id]);
    await client.query('INSERT INTO transactions(user_id,type,coins,reference,metadata) VALUES($1,\'transfer_out\',$2,$3,$4)',[from.id,coins,to,JSON.stringify({to})]);
    await client.query('INSERT INTO transactions(user_id,type,coins,reference,metadata) VALUES($1,\'transfer_in\',$2,$3,$4)',[target.id,coins,String(req.user.publicId),JSON.stringify({from:req.user.publicId})]);
    await client.query('COMMIT'); res.json({ok:true});
  } catch(e){ await client.query('ROLLBACK'); res.status(400).json({error:'TRANSFER_FAILED'}); } finally{client.release();}
});


app.post('/rooms/:roomId/livekit-token',auth,async(req,res)=>{
  const roomCode=String(req.params.roomId||'').trim();
  const room=(await db('SELECT room_code,title,host_user_id,is_live FROM rooms WHERE room_code=$1',[roomCode])).rows[0];
  if(!room || !room.is_live) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  const u=(await db('SELECT public_id,display_name FROM users WHERE id=$1',[req.user.sub])).rows[0];
  if(!u) return res.status(401).json({error:'UNAUTHORIZED'});
  const isHost=room.host_user_id===req.user.sub;
  const token=new AccessToken(process.env.LIVEKIT_API_KEY,process.env.LIVEKIT_API_SECRET,{identity:u.public_id,name:u.display_name||u.public_id});
  token.addGrant({roomJoin:true,room:roomCode,canSubscribe:true,canPublish:isHost || req.body?.publish===true});
  res.json({url:process.env.LIVEKIT_URL,token:await token.toJwt(),room:roomCode,isHost});
});

app.get('/rooms',auth,async(_req,res)=>{
  const r=await db(`SELECT r.room_code AS id,r.title,r.mode,r.viewer_count,r.is_live,
    u.public_id AS host_id,u.display_name AS host_name
    FROM rooms r JOIN users u ON u.id=r.host_user_id
    WHERE r.is_live=true ORDER BY r.viewer_count DESC,r.created_at DESC LIMIT 100`);
  res.json(r.rows);
});

app.post('/rooms',auth,async(req,res)=>{
  const title=String(req.body.title||'').trim().slice(0,120);
  const mode=['voice','video','live'].includes(req.body.mode)?req.body.mode:'voice';
  if(!title) return res.status(400).json({error:'INVALID_TITLE'});
  const code='R'+crypto.randomBytes(7).toString('hex').toUpperCase();
  const r=await db('INSERT INTO rooms(room_code,title,host_user_id,mode) VALUES($1,$2,$3,$4) RETURNING room_code AS id,title,mode,viewer_count,is_live',[code,title,req.user.sub,mode]);
  await db(`INSERT INTO room_seats(room_id,seat_no) SELECT id,g FROM rooms CROSS JOIN generate_series(1,20) g WHERE room_code=$1 ON CONFLICT DO NOTHING`,[code]);
  res.status(201).json(r.rows[0]);
});


async function roomCanModerate(roomId,userId){
  const r=await db(`SELECT 1 FROM rooms WHERE id=$1 AND host_user_id=$2 UNION ALL SELECT 1 FROM room_roles WHERE room_id=$1 AND user_id=$2 AND role='moderator' LIMIT 1`,[roomId,userId]);
  return r.rowCount>0;
}
app.get('/rooms/:roomId/seats',auth,async(req,res)=>{
  const room=(await db('SELECT id,host_user_id FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0];
  if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  await db(`INSERT INTO room_seats(room_id,seat_no) SELECT $1,g FROM generate_series(1,20) g ON CONFLICT DO NOTHING`,[room.id]);
  const r=await db(`SELECT s.seat_no AS seat,s.status,u.public_id AS user_id,u.display_name AS name,u.vip_level AS "vipLevel" FROM room_seats s LEFT JOIN users u ON u.id=s.user_id WHERE s.room_id=$1 ORDER BY s.seat_no`,[room.id]);
  res.json(r.rows);
});
app.get('/rooms/:roomId/seat-requests',auth,async(req,res)=>{
  const room=(await db('SELECT id FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0];
  if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  const r=await db(`SELECT q.id,u.public_id AS user_id,u.display_name AS name,q.status,q.created_at FROM seat_requests q JOIN users u ON u.id=q.user_id WHERE q.room_id=$1 AND q.status='pending' ORDER BY q.id`,[room.id]);
  res.json(r.rows);
});
app.post('/rooms/:roomId/seat-request',auth,async(req,res)=>{
  const room=(await db('SELECT id,host_user_id FROM rooms WHERE room_code=$1 AND is_live=true',[req.params.roomId])).rows[0];
  if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  if(req.user.sub===room.host_user_id) return res.status(400).json({error:'HOST_ALREADY_HAS_CONTROL'});
  const occupied=(await db(`SELECT 1 FROM room_seats WHERE room_id=$1 AND user_id=$2 AND status IN ('occupied','muted')`,[room.id,req.user.sub])).rowCount;
  if(occupied) return res.json({ok:true,status:'occupied'});
  await db(`UPDATE seat_requests SET status='cancelled' WHERE room_id=$1 AND user_id=$2 AND status='pending'`,[room.id,req.user.sub]);
  const r=await db(`INSERT INTO seat_requests(room_id,user_id,status) VALUES($1,$2,'pending') RETURNING id`,[room.id,req.user.sub]);
  broadcast(req.params.roomId,{type:'seat_request',requestId:r.rows[0].id,user:{id:req.user.publicId,name:(await db('SELECT display_name FROM users WHERE id=$1',[req.user.sub])).rows[0].display_name}});
  res.json({ok:true,status:'pending',requestId:r.rows[0].id});
});
app.post('/rooms/:roomId/seat-response',auth,async(req,res)=>{
  const room=(await db('SELECT id,host_user_id FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0];
  if(!room || !(await roomCanModerate(room.id,req.user.sub))) return res.status(403).json({error:'FORBIDDEN'});
  const requestId=Number(req.body.requestId), action=String(req.body.action||'');
  if(!Number.isSafeInteger(requestId)||!['accept','reject'].includes(action)) return res.status(400).json({error:'INVALID_SEAT_RESPONSE'});
  const q=(await db(`SELECT id,user_id FROM seat_requests WHERE id=$1 AND room_id=$2 AND status='pending'`,[requestId,room.id])).rows[0];
  if(!q) return res.status(404).json({error:'REQUEST_NOT_FOUND'});
  if(action==='reject'){ await db(`UPDATE seat_requests SET status='rejected' WHERE id=$1`,[q.id]); broadcast(req.params.roomId,{type:'seat_response',requestId:q.id,action:'reject',target:(await db('SELECT public_id FROM users WHERE id=$1',[q.user_id])).rows[0].public_id}); return res.json({ok:true}); }
  const free=(await db(`SELECT seat_no FROM room_seats WHERE room_id=$1 AND user_id IS NULL ORDER BY seat_no LIMIT 1`,[room.id])).rows[0];
  if(!free) return res.status(409).json({error:'NO_FREE_SEAT'});
  await db(`UPDATE seat_requests SET status='accepted' WHERE id=$1`,[q.id]);
  await db(`UPDATE room_seats SET user_id=$1,status='occupied',updated_at=now() WHERE room_id=$2 AND seat_no=$3`,[q.user_id,room.id,free.seat_no]);
  const target=(await db('SELECT public_id,display_name FROM users WHERE id=$1',[q.user_id])).rows[0];
  broadcast(req.params.roomId,{type:'seat_response',requestId:q.id,action:'accept',target:target.public_id,seat:free.seat_no,name:target.display_name});
  res.json({ok:true,seat:free.seat_no});
});
app.post('/rooms/:roomId/seat-leave',auth,async(req,res)=>{
  const room=(await db('SELECT id FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0];
  if(!room) return res.status(404).json({error:'ROOM_NOT_FOUND'});
  await db(`UPDATE room_seats SET user_id=NULL,status='open',updated_at=now() WHERE room_id=$1 AND user_id=$2`,[room.id,req.user.sub]);
  await db(`UPDATE seat_requests SET status='cancelled' WHERE room_id=$1 AND user_id=$2 AND status='pending'`,[room.id,req.user.sub]);
  broadcast(req.params.roomId,{type:'seat_left',target:req.user.publicId});
  res.json({ok:true});
});

app.get('/rooms/:roomId/members',auth,async(req,res)=>{
  const r=await db(`SELECT u.public_id AS id,u.display_name AS name,u.vip_level AS "vipLevel",COALESCE(rr.role,CASE WHEN u.id=rm.host_user_id THEN 'host' ELSE 'viewer' END) AS role
    FROM room_members m JOIN users u ON u.id=m.user_id JOIN rooms rm ON rm.id=m.room_id
    LEFT JOIN room_roles rr ON rr.room_id=rm.id AND rr.user_id=u.id WHERE rm.room_code=$1 ORDER BY role DESC,u.display_name`,[req.params.roomId]);
  res.json(r.rows);
});
app.post('/rooms/:roomId/moderation',auth,async(req,res)=>{
  const action=String(req.body.action||''); const target=String(req.body.userId||'').trim();
  if(!target || !['mute','unmute','kick','ban','unban','promote','demote'].includes(action)) return res.status(400).json({error:'INVALID_MODERATION'});
  const room=(await db('SELECT * FROM rooms WHERE room_code=$1',[req.params.roomId])).rows[0];
  if(!room || !(await roomCanModerate(room.id,req.user.sub))) return res.status(403).json({error:'FORBIDDEN'});
  const u=(await db('SELECT id,public_id FROM users WHERE public_id=$1',[target])).rows[0];
  if(!u || u.id===room.host_user_id) return res.status(400).json({error:'INVALID_TARGET'});
  if(action==='promote') await db(`INSERT INTO room_roles(room_id,user_id,role) VALUES($1,$2,'moderator') ON CONFLICT(room_id,user_id) DO UPDATE SET role='moderator'`,[room.id,u.id]);
  if(action==='demote') await db(`DELETE FROM room_roles WHERE room_id=$1 AND user_id=$2`,[room.id,u.id]);
  if(action==='ban') { await db(`INSERT INTO room_bans(room_id,user_id,reason) VALUES($1,$2,$3) ON CONFLICT(room_id,user_id) DO UPDATE SET reason=EXCLUDED.reason,created_at=now()`,[room.id,u.id,String(req.body.reason||'')]); await db('DELETE FROM room_members WHERE room_id=$1 AND user_id=$2',[room.id,u.id]); await db(`UPDATE room_seats SET user_id=NULL,status='open',updated_at=now() WHERE room_id=$1 AND user_id=$2`,[room.id,u.id]); }
  if(action==='unban') await db('DELETE FROM room_bans WHERE room_id=$1 AND user_id=$2',[room.id,u.id]);
  if(action==='mute' || action==='unmute') {
    await db(`UPDATE room_seats SET status=$1,updated_at=now() WHERE room_id=$2 AND user_id=$3`,[action==='mute'?'muted':'occupied',room.id,u.id]);
    broadcast(req.params.roomId,{type:'seat_status',target,muted:action==='mute'});
  }
  if(action==='ban') broadcast(req.params.roomId,{type:'seat_status',target,muted:false,removed:true});
  broadcast(req.params.roomId,{type:'moderation',action,target});
  res.json({ok:true,action,target});
});

app.get('/gifts',auth,async(_req,res)=>{
  const r=await db('SELECT id,code,name,emoji,coins FROM gift_catalog WHERE active=true ORDER BY coins');
  res.json(r.rows);
});

app.post('/rooms/:roomId/gifts',auth,async(req,res)=>{
  const roomId=String(req.params.roomId), giftId=Number(req.body.giftId), receiver=String(req.body.receiverPublicId||'').trim();
  if(!Number.isSafeInteger(giftId)||!receiver) return res.status(400).json({error:'INVALID_GIFT'});
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const room=(await client.query('SELECT id FROM rooms WHERE room_code=$1 AND is_live=true FOR UPDATE',[roomId])).rows[0];
    const gift=(await client.query('SELECT id,name,emoji,coins FROM gift_catalog WHERE id=$1 AND active=true',[giftId])).rows[0];
    const target=(await client.query('SELECT id,public_id,name FROM users WHERE public_id=$1 FOR UPDATE',[receiver])).rows[0];
    const sender=(await client.query('SELECT id,public_id,name,coins FROM users WHERE id=$1 FOR UPDATE',[req.user.sub])).rows[0];
    if(!room||!gift||!target||!sender||sender.id===target.id||sender.coins<Number(gift.coins)) throw new Error('INVALID_GIFT_SEND');
    await client.query('UPDATE users SET coins=coins-$1 WHERE id=$2',[gift.coins,sender.id]);
    await client.query('UPDATE users SET xp=xp+$1 WHERE id=$2',[Math.max(1,Math.floor(Number(gift.coins)/10)),target.id]);
    const ev=(await client.query('INSERT INTO gift_events(room_id,sender_user_id,receiver_user_id,gift_id,coins) VALUES($1,$2,$3,$4,$5) RETURNING id,created_at',[room.id,sender.id,target.id,gift.id,gift.coins])).rows[0];
    await client.query('INSERT INTO transactions(user_id,type,coins,reference,metadata) VALUES($1,\'gift_sent\',$2,$3,$4)',[sender.id,-Number(gift.coins),receiver,JSON.stringify({roomId,giftId})]);
    await client.query('INSERT INTO transactions(user_id,type,coins,reference,metadata) VALUES($1,\'gift_received\',$2,$3,$4)',[target.id,Number(gift.coins),String(req.user.publicId),JSON.stringify({roomId,giftId})]);
    await client.query('INSERT INTO room_stats(room_id,gifts_coins) VALUES($1,$2) ON CONFLICT(room_id) DO UPDATE SET gifts_coins=room_stats.gifts_coins+$2,updated_at=now()',[room.id,Number(gift.coins)]);
    await client.query('COMMIT');
    broadcast(roomId,{type:'gift',eventId:ev.id,emoji:gift.emoji,gift:gift.name,coins:Number(gift.coins),user:{id:sender.public_id,name:sender.name},receiver:{id:target.public_id,name:target.name}});
    res.json({ok:true,eventId:ev.id,gift:{id:gift.id,name:gift.name,emoji:gift.emoji,coins:Number(gift.coins)},createdAt:ev.created_at});
  } catch(e) { await client.query('ROLLBACK'); res.status(400).json({error:'GIFT_SEND_FAILED'}); }
  finally { client.release(); }
});


const server = app.listen(PORT,()=>console.log(`LiveStar backend listening on ${PORT}`));
const wss = new WebSocketServer({ server, path: '/ws' });
function send(ws, payload){ if(ws.readyState===1) ws.send(JSON.stringify(payload)); }
function broadcast(roomCode,payload){ const set=sockets.get(roomCode); if(!set) return; for(const ws of set) send(ws,payload); }
async function wsAuth(tokenValue){ return jwt.verify(tokenValue||'',SECRET); }
wss.on('connection', async (ws, req)=>{
  try {
    const u=new URL(req.url,'http://localhost'); const roomCode=u.searchParams.get('room'); const claims=await wsAuth(u.searchParams.get('token'));
    if(!roomCode) throw new Error('ROOM_REQUIRED');
    const room=(await db('SELECT id,room_code,title,mode,is_live FROM rooms WHERE room_code=$1',[roomCode])).rows[0];
    const user=(await db('SELECT id,public_id,display_name FROM users WHERE id=$1',[claims.sub])).rows[0];
    if(!room||!room.is_live||!user) throw new Error('ROOM_NOT_FOUND');
    const banned=(await db('SELECT 1 FROM room_bans WHERE room_id=$1 AND user_id=$2',[room.id,user.id])).rowCount>0;
    if(banned) throw new Error('BANNED');
    ws.roomCode=roomCode; ws.user=user;
    if(!sockets.has(roomCode)) sockets.set(roomCode,new Set()); sockets.get(roomCode).add(ws);
    await db(`INSERT INTO room_members(room_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[room.id,user.id]);
    await db('UPDATE rooms SET viewer_count=(SELECT count(*) FROM room_members WHERE room_id=$1) WHERE id=$1',[room.id]);
    send(ws,{type:'joined',room:{id:room.room_code,title:room.title,mode:room.mode,hostId: (await db('SELECT public_id FROM users WHERE id=$1',[room.host_user_id])).rows[0]?.public_id},user:{id:user.public_id,name:user.display_name}});
    broadcast(roomCode,{type:'presence',action:'join',user:{id:user.public_id,name:user.display_name}});
    ws.on('message',async raw=>{
      try { const m=JSON.parse(raw.toString());
        if(m.type==='chat'){ const text=String(m.text||'').trim().slice(0,500); if(!text) return; const row=(await db(`INSERT INTO chat_messages(room_id,user_id,message) VALUES($1,$2,$3) RETURNING id,created_at`,[room.id,user.id,text])).rows[0]; broadcast(roomCode,{type:'chat',id:row.id,user:{id:user.public_id,name:user.display_name},text,createdAt:row.created_at}); }
        else if(m.type==='sticker'){ await applyVipDecay(user.id); const u2=(await db('SELECT vip_level FROM users WHERE id=$1',[user.id])).rows[0]; const code=String(m.code||''); const st=(await db('SELECT id,code,name,visual,vip_required FROM animated_stickers WHERE code=$1 AND active=true',[code])).rows[0]; if(!st) return; if(Number(u2.vip_level)<Number(st.vip_required)) return send(ws,{type:'error',error:'VIP_REQUIRED',requiredVip:Number(st.vip_required)}); const row=(await db('INSERT INTO chat_sticker_events(room_id,user_id,sticker_id) VALUES($1,$2,$3) RETURNING id,created_at',[room.id,user.id,st.id])).rows[0]; broadcast(roomCode,{type:'sticker',id:row.id,user:{id:user.public_id,name:user.display_name,vipLevel:Number(u2.vip_level)},sticker:{code:st.code,name:st.name,visual:st.visual},createdAt:row.created_at}); }
        else if(m.type==='signal'){ const to=String(m.to||'').trim(); const payload={type:'signal',from:user.public_id,to,data:m.data}; if(to){ for(const peer of (sockets.get(roomCode)||[])) if(peer.user?.public_id===to) send(peer,payload); } else broadcast(roomCode,payload); }
        else if(m.type==='moderation'){
          if(!(await roomCanModerate(room.id,user.id))) return send(ws,{type:'error',error:'FORBIDDEN'});
          const target=String(m.target||'').trim(), action=String(m.action||'');
          if(!target || !['mute','unmute','kick','ban'].includes(action)) return;
          const tu=(await db('SELECT id,public_id FROM users WHERE public_id=$1',[target])).rows[0]; if(!tu || tu.id===room.host_user_id) return;
          if(action==='ban'){ await db(`INSERT INTO room_bans(room_id,user_id,reason) VALUES($1,$2,$3) ON CONFLICT(room_id,user_id) DO UPDATE SET reason=EXCLUDED.reason`,[room.id,tu.id,String(m.reason||'')]); await db('DELETE FROM room_members WHERE room_id=$1 AND user_id=$2',[room.id,tu.id]); }
          broadcast(roomCode,{type:'moderation',action,target,by:user.public_id});
          if(action==='kick'||action==='ban') for(const peer of (sockets.get(roomCode)||[])) if(peer.user?.public_id===target) { send(peer,{type:'moderation',action,target}); peer.close(); }
        }
        else if(m.type==='seat_request'){
          const q=(await db(`INSERT INTO seat_requests(room_id,user_id,status) VALUES($1,$2,'pending') RETURNING id`,[room.id,user.id])).rows[0];
          broadcast(roomCode,{type:'seat_request',requestId:q.id,user:{id:user.public_id,name:user.display_name}});
        }
        else if(m.type==='seat_response'){
          if(!(await roomCanModerate(room.id,user.id))) return send(ws,{type:'error',error:'FORBIDDEN'});
          const requestId=Number(m.requestId), action=String(m.action||'');
          const q=(await db(`SELECT id,user_id FROM seat_requests WHERE id=$1 AND room_id=$2 AND status='pending'`,[requestId,room.id])).rows[0];
          if(!q || !['accept','reject'].includes(action)) return;
          const target=(await db('SELECT public_id,display_name FROM users WHERE id=$1',[q.user_id])).rows[0];
          if(action==='reject'){ await db(`UPDATE seat_requests SET status='rejected' WHERE id=$1`,[q.id]); broadcast(roomCode,{type:'seat_response',requestId:q.id,action,target:target.public_id}); }
          else { const free=(await db(`SELECT seat_no FROM room_seats WHERE room_id=$1 AND user_id IS NULL ORDER BY seat_no LIMIT 1`,[room.id])).rows[0]; if(!free) return send(ws,{type:'error',error:'NO_FREE_SEAT'}); await db(`UPDATE seat_requests SET status='accepted' WHERE id=$1`,[q.id]); await db(`UPDATE room_seats SET user_id=$1,status='occupied',updated_at=now() WHERE room_id=$2 AND seat_no=$3`,[q.user_id,room.id,free.seat_no]); broadcast(roomCode,{type:'seat_response',requestId:q.id,action,target:target.public_id,seat:free.seat_no,name:target.display_name}); }
        }
        else if(m.type==='seat_leave'){ await db(`UPDATE room_seats SET user_id=NULL,status='open',updated_at=now() WHERE room_id=$1 AND user_id=$2`,[room.id,user.id]); broadcast(roomCode,{type:'seat_left',target:user.public_id}); }
        else if(m.type==='ping'){ send(ws,{type:'pong'}); }
      } catch(e){ send(ws,{type:'error',error:'BAD_MESSAGE'}); }
    });
    ws.on('close',async()=>{ try { sockets.get(roomCode)?.delete(ws); await db(`UPDATE room_seats SET user_id=NULL,status='open',updated_at=now() WHERE room_id=$1 AND user_id=$2`,[room.id,user.id]); await db('DELETE FROM room_members WHERE room_id=$1 AND user_id=$2',[room.id,user.id]); await db('UPDATE rooms SET viewer_count=(SELECT count(*) FROM room_members WHERE room_id=$1) WHERE id=$1',[room.id]); broadcast(roomCode,{type:'presence',action:'leave',user:{id:user.public_id,name:user.display_name}}); if(sockets.get(roomCode)?.size===0) sockets.delete(roomCode); } catch{} });
  } catch(e){ send(ws,{type:'error',error:'UNAUTHORIZED_OR_ROOM_NOT_FOUND'}); ws.close(); }
});


app.use((err,_req,res,_next)=>{ console.error(err); if(!res.headersSent) res.status(500).json({error:'INTERNAL_SERVER_ERROR'}); });


async function shutdown(signal){ console.log(signal+': shutting down'); wss.close(); server.close(function(){ pool.end().then(function(){ process.exit(0); }); }); setTimeout(function(){ process.exit(1); },10000).unref(); }
process.on('SIGTERM',function(){ shutdown('SIGTERM'); });
process.on('SIGINT',function(){ shutdown('SIGINT'); });
