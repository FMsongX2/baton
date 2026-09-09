// 코인 잔액 변경. 잔액은 users에 두고 변동 내역은 항상 ledger에 남김.
// 차감은 조건부 UPDATE 한 방으로 처리해 동시에 두 번 눌러도 잔액이 음수가 되지 않게 함.

import type { Env } from './env.js';

/// 잔액을 읽음. 사용자가 없으면 null.
export async function balanceOf(env: Env, userId: string): Promise<number | null> {
  const row = await env.DB.prepare('SELECT balance FROM users WHERE id = ?')
    .bind(userId)
    .first<{ balance: number }>();
  return row ? row.balance : null;
}

/// 잔액이 충분할 때만 차감하고 남은 잔액을 돌려줌. 모자라면 null.
/// WHERE에 balance 조건을 넣어 확인과 차감을 한 문장으로 묶음.
/// 원장 기록을 먼저 넣고 차감을 뒤에 둠. 둘이 같은 조건을 보고, 원장의 SELECT는 차감 전 잔액을
/// 읽으므로 한 batch(트랜잭션) 안에서 둘 다 적용되거나 둘 다 빠짐.
export async function spend(
  env: Env,
  userId: string,
  amount: number,
  reason: string,
  ref?: string,
): Promise<number | null> {
  const [, updated] = await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO ledger (user_id, delta, reason, ref, created_at) ' +
        'SELECT ?1, -?2, ?3, ?4, ?5 FROM users WHERE id = ?1 AND balance >= ?2',
    ).bind(userId, amount, reason, ref ?? null, Date.now()),
    env.DB.prepare('UPDATE users SET balance = balance - ?2 WHERE id = ?1 AND balance >= ?2').bind(
      userId,
      amount,
    ),
  ]);
  if (!updated.meta.changes) return null;

  return (await balanceOf(env, userId)) ?? 0;
}

/// 코인을 넣고 남은 잔액을 돌려줌. 구매 적립과 실패 환불이 같은 길을 씀.
export async function grant(
  env: Env,
  userId: string,
  amount: number,
  reason: string,
  ref?: string,
): Promise<number> {
  await env.DB.batch(grantStatements(env, userId, amount, reason, ref));
  return (await balanceOf(env, userId)) ?? 0;
}

/// 적립을 이루는 문장들. 다른 문장과 한 batch로 묶어 함께 커밋해야 할 때 씀.
export function grantStatements(
  env: Env,
  userId: string,
  amount: number,
  reason: string,
  ref?: string,
): D1PreparedStatement[] {
  return [
    env.DB.prepare('UPDATE users SET balance = balance + ? WHERE id = ?').bind(amount, userId),
    env.DB.prepare(
      'INSERT INTO ledger (user_id, delta, reason, ref, created_at) VALUES (?, ?, ?, ?, ?)',
    ).bind(userId, amount, reason, ref ?? null, Date.now()),
  ];
}
