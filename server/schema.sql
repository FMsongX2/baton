-- 코인 원장. 잔액은 users.balance에 두되 변동은 항상 ledger에 남겨 사후 추적이 되게 함.

-- pending_recovery_hash는 재발급했지만 사용자가 받아 적었다고 확인하기 전인 코드.
-- 확인 전까지 recovery_hash(이전 코드)가 그대로 통하므로 응답이 유실돼도 코드를 잃지 않음
CREATE TABLE IF NOT EXISTS users (
  id                    TEXT PRIMARY KEY,
  token_hash            TEXT NOT NULL,
  recovery_hash         TEXT NOT NULL,
  pending_recovery_hash TEXT,
  balance               INTEGER NOT NULL DEFAULT 0,
  created_at            INTEGER NOT NULL
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
-- 이미 끝난 분석이면 저장해 둔 결과를 그대로 돌려줌.
-- pages: 요청한 쪽 번호(0부터, 쉼표로 이음). 같은 id로 다른 쪽이 오면 거절함
-- cost: 실제로 빠진 코인. 모델이 빠뜨린 쪽만큼 돌려주면 그만큼 줄어듦
-- claim: 분석을 맡은 요청의 표식. 이 값을 쥔 요청만 결과를 쓰거나 환불함
-- created_at: 맡은 시각. 기한(analyses.ts의 ANALYSIS_LEASE_MS)이 지나도록 결과가 없으면 환불하고 지움
CREATE TABLE IF NOT EXISTS analyses (
  user_id    TEXT NOT NULL,
  request_id TEXT NOT NULL,
  pages      TEXT NOT NULL,
  cost       INTEGER NOT NULL,
  claim      TEXT NOT NULL,
  result     TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, request_id)
);
