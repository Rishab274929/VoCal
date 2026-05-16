-- VoCal initial schema. Mirror of plan §6.

CREATE TABLE IF NOT EXISTS users (
  id              TEXT PRIMARY KEY,
  apple_sub       TEXT UNIQUE,
  display_name    TEXT,
  sex             TEXT,
  height_in       REAL,
  weight_lb       REAL,
  birth_date      TEXT,
  daily_kcal_goal INTEGER NOT NULL DEFAULT 2200,
  protein_g_goal  INTEGER NOT NULL DEFAULT 160,
  carbs_g_goal    INTEGER NOT NULL DEFAULT 240,
  fat_g_goal      INTEGER NOT NULL DEFAULT 70,
  entitlement     TEXT NOT NULL DEFAULT 'free',
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS meals (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id),
  name         TEXT NOT NULL,
  detail       TEXT,
  kcal         INTEGER NOT NULL,
  protein_g    INTEGER NOT NULL,
  carbs_g      INTEGER NOT NULL,
  fat_g        INTEGER NOT NULL,
  slot         TEXT NOT NULL,
  source       TEXT NOT NULL,
  photo_r2_key TEXT,
  transcript   TEXT,
  confidence   REAL,
  logged_at    INTEGER NOT NULL,
  created_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_meals_user_day ON meals(user_id, logged_at);

CREATE TABLE IF NOT EXISTS body_metrics (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id),
  weight_lb     REAL,
  body_fat_pct  REAL,
  bf_confidence REAL,
  front_r2_key  TEXT,
  side_r2_key   TEXT,
  notes         TEXT,
  measured_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_body_user_day ON body_metrics(user_id, measured_at);

CREATE TABLE IF NOT EXISTS coach_messages (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id),
  role       TEXT NOT NULL,
  content    TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_coach_user_time ON coach_messages(user_id, created_at);

CREATE TABLE IF NOT EXISTS integrations (
  user_id       TEXT NOT NULL REFERENCES users(id),
  provider      TEXT NOT NULL,
  access_token  TEXT,
  refresh_token TEXT,
  expires_at    INTEGER,
  PRIMARY KEY (user_id, provider)
);
