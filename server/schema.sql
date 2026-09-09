-- 코인 원장. 잔액은 users.balance에 두되 변동은 항상 ledger에 남겨 사후 추적이 되게 함.

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  token_hash    TEXT NOT NULL,
  recovery_hash TEXT NOT NULL,
  balance       INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_token ON users(token_hash);
CREATE INDEX IF NOT EXISTS idx_users_recovery ON users(recovery_hash);

-- 코인이 늘고 준 내역. delta가 음수면 사용, 양수면 적립
CREATE TABLE IF NOT EXISTS ledger (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    TEXT NOT NULL,
  delta      INTEGER NOT NULL,
  reason     TEXT NOT NULL,
  ref        TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ledger_user ON ledger(user_id, created_at);

-- 영수증 중복 적립을 막는 곳. purchase_token이 유일키라 재전송해도 한 번만 적립됨
CREATE TABLE IF NOT EXISTS purchases (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id        TEXT NOT NULL,
  platform       TEXT NOT NULL,
  product_id     TEXT NOT NULL,
  purchase_token TEXT NOT NULL UNIQUE,
  coins          INTEGER NOT NULL,
  created_at     INTEGER NOT NULL
);

-- 기기 등록 횟수 제한. 계정이 없어 등록이 공짜라 그대로 두면 사용자 행을 무한히 만들 수 있음
CREATE TABLE IF NOT EXISTS registrations (
  ip_hash TEXT NOT NULL,
  day     INTEGER NOT NULL,
  count   INTEGER NOT NULL,
  PRIMARY KEY (ip_hash, day)
);

-- 분석 요청의 멱등키. 응답이 유실돼 재요청이 와도 코인을 두 번 빼지 않고
-- 이미 끝난 분석이면 저장해 둔 결과를 그대로 돌려줌
CREATE TABLE IF NOT EXISTS analyses (
  request_id TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  cost       INTEGER NOT NULL,
  result     TEXT,
  created_at INTEGER NOT NULL
);
