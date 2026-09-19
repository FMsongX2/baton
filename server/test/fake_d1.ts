// 테스트용 D1 대역. node:sqlite 메모리 DB에 schema.sql을 올리고 D1이 쓰는 모양만 흉내 냄.
// batch는 D1처럼 한 트랜잭션으로 묶어 실패하면 통째로 되돌림.

import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

type Row = Record<string, unknown>;

/// schema.sql을 적용한 새 메모리 DB를 D1 모양으로 돌려줌.
export function fakeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));

  /// 문장 하나를 실행해 D1 결과 모양으로 바꿈. 행을 돌려주는 문장이면 results에 담음.
  const exec = (sql: string, args: unknown[]) => {
    const st = db.prepare(sql);
    const params = args as (string | number | null)[];
    if (st.columns().length > 0) {
      return { results: st.all(...params) as Row[], meta: { changes: 0 } };
    }
    const r = st.run(...params);
    return { results: [] as Row[], meta: { changes: Number(r.changes) } };
  };

  /// 바인딩 값을 들고 있는 문장. D1처럼 bind가 새 문장을 돌려줌.
  const statement = (sql: string, args: unknown[] = []) => ({
    bind: (...next: unknown[]) => statement(sql, next),
    first: async () => exec(sql, args).results[0] ?? null,
    run: async () => exec(sql, args),
    all: async () => exec(sql, args),
    exec: () => exec(sql, args),
  });

  return {
    raw: db,
    prepare: (sql: string) => statement(sql),
    /// 문장들을 한 트랜잭션으로 실행함.
    batch: async (stmts: { exec: () => ReturnType<typeof exec> }[]) => {
      db.exec('BEGIN');
      try {
        const out = stmts.map((s) => s.exec());
        db.exec('COMMIT');
        return out;
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },
  };
}

/// 잔액을 가진 사용자 하나를 넣음.
export function addUser(d1: ReturnType<typeof fakeD1>, id: string, balance: number) {
  d1.raw
    .prepare(
      "INSERT INTO users (id, token_hash, recovery_hash, balance, created_at) VALUES (?, 't', 'r', ?, 0)",
    )
    .run(id, balance);
}

/// 사용자의 잔액과 원장 합계. 둘을 함께 봐야 잔액은 맞는데 원장이 새는 경우를 잡음.
export function money(d1: ReturnType<typeof fakeD1>, id: string) {
  const balance = (d1.raw.prepare('SELECT balance FROM users WHERE id = ?').get(id) as Row)
    .balance as number;
  const sum = d1.raw.prepare('SELECT COALESCE(SUM(delta), 0) AS s FROM ledger WHERE user_id = ?');
  const ledger = (sum.get(id) as Row).s as number;
  return { balance, ledger };
}
