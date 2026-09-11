CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  public_id VARCHAR(20) UNIQUE NOT NULL,
  phone VARCHAR(32) UNIQUE,
  display_name VARCHAR(80) NOT NULL DEFAULT 'LiveStar User',
  avatar_url TEXT,
  coins BIGINT NOT NULL DEFAULT 0 CHECK (coins >= 0),
  diamonds BIGINT NOT NULL DEFAULT 0 CHECK (diamonds >= 0),
  xp BIGINT NOT NULL DEFAULT 0 CHECK (xp >= 0),
  vip_level INT NOT NULL DEFAULT 0 CHECK (vip_level >= 0 AND vip_level <= 30),
  vip_expires_at TIMESTAMPTZ,
  vip_decay_at TIMESTAMPTZ,
  vip_started_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS otp_codes (
  id BIGSERIAL PRIMARY KEY,
  phone VARCHAR(32) NOT NULL,
  code_hash VARCHAR(100) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS transactions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  type VARCHAR(30) NOT NULL,
  coins BIGINT NOT NULL,
  amount_usd NUMERIC(12,2),
  reference VARCHAR(120),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_transactions_user_created ON transactions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS rooms (
  id BIGSERIAL PRIMARY KEY,
  room_code VARCHAR(24) UNIQUE NOT NULL,
  title VARCHAR(120) NOT NULL,
  host_user_id BIGINT NOT NULL REFERENCES users(id),
  mode VARCHAR(16) NOT NULL DEFAULT 'voice' CHECK (mode IN ('voice','video','live')),
  viewer_count INT NOT NULL DEFAULT 0 CHECK (viewer_count >= 0),
  is_live BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rooms_live ON rooms(is_live, created_at DESC);

CREATE TABLE IF NOT EXISTS gift_catalog (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(40) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  emoji VARCHAR(8) NOT NULL,
  coins BIGINT NOT NULL CHECK (coins > 0),
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS gift_events (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES rooms(id),
  sender_user_id BIGINT NOT NULL REFERENCES users(id),
  receiver_user_id BIGINT NOT NULL REFERENCES users(id),
  gift_id BIGINT NOT NULL REFERENCES gift_catalog(id),
  coins BIGINT NOT NULL CHECK (coins > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO gift_catalog(code,name,emoji,coins) VALUES
('rose','وردة ملكية','🌹',10),('diamond_heart','قلب ماسي','💖',100),('king_crown','تاج الملوك','👑',1000),
('shiny_butterfly','فراشة لامعة','🦋',5000),('rare_diamond','ماسة نادرة','💎',25000),
('luxury_car','سيارة فاخرة','🚘',75000),('private_jet','طائرة خاصة','🛩️',150000),
('legendary_unicorn','وحيد القرن الأسطوري','🦄',300000),('dream_castle','قصر الأحلام','🏰',750000),
('star_galaxy','مجرة النجوم','🌌',1500000)
ON CONFLICT (code) DO NOTHING;


CREATE TABLE IF NOT EXISTS room_members (
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_members_room ON room_members(room_id);
CREATE TABLE IF NOT EXISTS chat_messages (
  id BIGSERIAL PRIMARY KEY, room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id), message TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chat_room_created ON chat_messages(room_id,created_at DESC);


CREATE TABLE IF NOT EXISTS room_roles (
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL CHECK (role IN ('host','moderator')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,user_id)
);
CREATE TABLE IF NOT EXISTS room_bans (
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,user_id)
);


CREATE TABLE IF NOT EXISTS room_seats (
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  seat_no INT NOT NULL CHECK (seat_no BETWEEN 1 AND 20),
  user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'open' CHECK (status IN ('open','occupied','muted')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,seat_no)
);
CREATE TABLE IF NOT EXISTS seat_requests (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id,user_id,status)
);

CREATE TABLE IF NOT EXISTS follows (
  follower_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(follower_id, following_id),
  CHECK (follower_id <> following_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);
CREATE TABLE IF NOT EXISTS room_likes (
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,user_id)
);
CREATE TABLE IF NOT EXISTS room_stats (
  room_id BIGINT PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  likes BIGINT NOT NULL DEFAULT 0,
  gifts_coins BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


ALTER TABLE users ADD COLUMN IF NOT EXISTS vip_expires_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS vip_decay_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS vip_started_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS animated_stickers (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  visual VARCHAR(40) NOT NULL,
  vip_required INT NOT NULL DEFAULT 0 CHECK (vip_required BETWEEN 0 AND 30),
  active BOOLEAN NOT NULL DEFAULT true
);
INSERT INTO animated_stickers(code,name,visual,vip_required) VALUES
('spark_heart','قلب لامع','💖',0),
('royal_crown','تاج ملكي','👑',7),
('gold_fire','نار ذهبية','🔥',7),
('diamond_burst','انفجار ألماسي','💎',10),
('galaxy_wave','موجة مجرية','🌌',15),
('royal_love','حب ملكي','💞',20),
('legendary_stars','نجوم أسطورية','🌟',30)
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS chat_sticker_events (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sticker_id BIGINT NOT NULL REFERENCES animated_stickers(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sticker_events_room_created ON chat_sticker_events(room_id,created_at DESC);

CREATE TABLE IF NOT EXISTS coin_packages (
  id BIGSERIAL PRIMARY KEY,
  coins BIGINT NOT NULL,
  price_usd NUMERIC(10,2) NOT NULL,
  diamond_bonus BIGINT NOT NULL DEFAULT 0 CHECK (diamond_bonus >= 0),
  active BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(coins, price_usd)
);
ALTER TABLE coin_packages ADD COLUMN IF NOT EXISTS diamond_bonus BIGINT NOT NULL DEFAULT 0;
INSERT INTO coin_packages(coins,price_usd,diamond_bonus) VALUES
(30000,4,500),(75000,10,1250),(150000,20,2500),(375000,50,6250),(750000,100,12500),(1500000,200,25000),(3000000,400,50000),(4500000,600,75000)
ON CONFLICT DO NOTHING;
UPDATE coin_packages SET diamond_bonus = CASE coins
  WHEN 30000 THEN 500 WHEN 75000 THEN 1250 WHEN 150000 THEN 2500 WHEN 375000 THEN 6250
  WHEN 750000 THEN 12500 WHEN 1500000 THEN 25000 WHEN 3000000 THEN 50000 WHEN 4500000 THEN 75000 ELSE diamond_bonus END;
CREATE TABLE IF NOT EXISTS payment_orders (
  id UUID PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  package_id BIGINT NOT NULL REFERENCES coin_packages(id),
  method VARCHAR(32) NOT NULL CHECK (method IN ('card','google_pay','apple_pay','asiacell')),
  status VARCHAR(24) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','cancelled')),
  provider_reference VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_payment_orders_user_created ON payment_orders(user_id,created_at DESC);


CREATE TABLE IF NOT EXISTS diamond_store_items (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(40) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  item_type VARCHAR(16) NOT NULL CHECK (item_type IN ('frame','public_id')),
  price_diamonds BIGINT NOT NULL CHECK (price_diamonds > 0),
  active BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO diamond_store_items(code,name,item_type,price_diamonds) VALUES
('frame_royal','إطار ملكي','frame',100),
('frame_diamond','إطار ألماسي','frame',500),
('frame_galaxy','إطار المجرة','frame',1000),
('id_change','تغيير الـID','public_id',500)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE users ADD COLUMN IF NOT EXISTS diamonds BIGINT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS active_frame_code VARCHAR(40);
