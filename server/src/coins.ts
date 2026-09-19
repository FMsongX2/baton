// 코인 잔액 조회와 적립. 잔액은 users에 두고 변동 내역은 항상 ledger에 남김.
// 분석 차감·환불은 멱등키와 한 트랜잭션이어야 해서 analyses.ts가 맡음.

import type { Env } from './env.js';

/// 잔액을 읽음. 사용자가 없으면 null.
export async function balanceOf(env: Env, userId: string): Promise<number | null> {
  const row = await env.DB.prepare('SELECT balance FROM users WHERE id = ?')
    .bind(userId)
    .first<{ balance: number }>();
  return row ? row.balance : null;
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
