// 분석 요청의 멱등키와 코인 차감·환불. 같은 requestId는 한 번만 빼고 한 번만 돌려줌.
// 선점(claim)을 쥔 요청만 결과를 쓰거나 환불하므로, 동시에 몇 번이 와도 원장이 한 번만 움직임.

import type { Env } from './env.js';

/// 분석을 맡은 요청이 결과를 낼 때까지 기다려 주는 시간.
/// 이보다 오래 결과가 없으면 버려진 요청(클라이언트 단절로 워커가 취소된 경우 등)으로 보고 전액 환불함.
/// analyze.ts의 ANALYSIS_BUDGET_MS(재시도 포함 모델 호출 한도)보다 결과 기록 몫만큼 길어야
/// 살아 있는 분석을 환불하지 않음.
export const ANALYSIS_LEASE_MS = 4 * 60_000;

export type Claim =
  /// 이 요청이 분석을 맡음. 코인은 이미 빠졌고 claim을 쥔 채 complete나 abandon으로 끝내야 함
  | { kind: 'claimed'; claim: string; cost: number }
  /// 이미 끝난 분석. 저장된 결과를 그대로 돌려줌
  | { kind: 'done'; cost: number; result: string }
  /// 같은 requestId를 다른 요청이 처리하는 중
  | { kind: 'running' }
  /// 같은 requestId로 다른 쪽 묶음이 옴
  | { kind: 'mismatch' }
  /// 잔액이 모자람
  | { kind: 'insufficient'; balance: number };

/// 조건에 맞는 미완료 분석을 원장에 환불로 남기고 잔액을 되돌린 뒤 행을 지우는 문장들.
/// 셋이 같은 조건을 보므로 한 batch 안에서 같은 행 집합에 대해 한 번만 적용됨.
function refundStatements(
  env: Env,
  userId: string,
  where: string,
  binds: unknown[],
  now: number,
): D1PreparedStatement[] {
  const from = `FROM analyses WHERE user_id = ? AND result IS NULL AND ${where}`;
  return [
    env.DB.prepare(
      `INSERT INTO ledger (user_id, delta, reason, ref, created_at) SELECT user_id, cost, 'analyze_refund', request_id, ? ${from}`,
    ).bind(now, userId, ...binds),
    // 환불할 행이 없으면 users를 건드리지 않음. 잔액 조회마다 도는 문장이라 쓰기를 남기지 않게 함
    env.DB.prepare(
      `UPDATE users SET balance = balance + (SELECT COALESCE(SUM(cost), 0) ${from}) WHERE id = ? AND EXISTS (SELECT 1 ${from})`,
    ).bind(userId, ...binds, userId, userId, ...binds),
    env.DB.prepare(`DELETE ${from}`).bind(userId, ...binds),
  ];
}

/// 기한이 지나도록 결과가 없는 이 사용자의 분석을 전액 환불함.
/// 앱이 끝내 다시 보내지 않아도 잔액 조회 때 코인이 돌아오게 함.
export function staleRefundStatements(
  env: Env,
  userId: string,
  now: number,
): D1PreparedStatement[] {
  return refundStatements(env, userId, 'created_at <= ?', [now - ANALYSIS_LEASE_MS], now);
}

/// 버려진 분석을 정리하고 잔액을 돌려줌.
export async function refundStaleAnalyses(
  env: Env,
  userId: string,
  now = Date.now(),
): Promise<void> {
  await env.DB.batch(staleRefundStatements(env, userId, now));
}

/// requestId를 선점하고 코인을 뺌. 버려진 분석 환불, 선점, 차감, 결과 판단을 한 batch(트랜잭션)로 묶어
/// 같은 id가 동시에 와도 한 요청만 claimed를 받고 차감도 한 번만 일어남.
export async function claimAnalysis(
  env: Env,
  userId: string,
  requestId: string,
  pageKey: string,
  cost: number,
  now = Date.now(),
): Promise<Claim> {
  const claim = crypto.randomUUID();
  const mine = 'FROM analyses WHERE user_id = ? AND request_id = ? AND claim = ?';
  const results = await env.DB.batch([
    ...staleRefundStatements(env, userId, now),
    // 잔액 조건을 선점에 걸어 둠. 같은 트랜잭션이라 이 뒤의 차감이 음수를 만들 수 없음
    env.DB.prepare(
      'INSERT INTO analyses (user_id, request_id, pages, cost, claim, result, created_at) ' +
        'SELECT id, ?, ?, ?, ?, NULL, ? FROM users WHERE id = ? AND balance >= ? ' +
        'ON CONFLICT DO NOTHING',
    ).bind(requestId, pageKey, cost, claim, now, userId, cost),
    env.DB.prepare(
      `INSERT INTO ledger (user_id, delta, reason, ref, created_at) SELECT user_id, -cost, 'analyze', request_id, ? ${mine}`,
    ).bind(now, userId, requestId, claim),
    env.DB.prepare(
      `UPDATE users SET balance = balance - ? WHERE id = ? AND EXISTS (SELECT 1 ${mine})`,
    ).bind(cost, userId, userId, requestId, claim),
    env.DB.prepare(
      'SELECT pages, cost, claim, result FROM analyses WHERE user_id = ? AND request_id = ?',
    ).bind(userId, requestId),
    env.DB.prepare('SELECT balance FROM users WHERE id = ?').bind(userId),
  ]);

  const row = results.at(-2)?.results[0] as
    | { pages: string; cost: number; claim: string; result: string | null }
    | undefined;
  const balance = (results.at(-1)?.results[0] as { balance: number } | undefined)?.balance ?? 0;

  if (!row) return { kind: 'insufficient', balance };
  if (row.claim === claim) return { kind: 'claimed', claim, cost };
  if (row.pages !== pageKey) return { kind: 'mismatch' };
  if (row.result !== null) return { kind: 'done', cost: row.cost, result: row.result };
  return { kind: 'running' };
}

/// 결과를 저장하고, 모델이 돌려주지 못한 쪽 몫(refund)을 돌려줌.
/// 선점을 쥔 경우에만 적용되며, 선점을 잃었으면(기한이 지나 환불된 뒤 등) false.
export async function completeAnalysis(
  env: Env,
  userId: string,
  requestId: string,
  claim: string,
  result: string,
  refund: number,
  now = Date.now(),
): Promise<boolean> {
  // 환불을 결과 기록보다 앞에 둠. 셋 다 '아직 결과가 없는 내 선점'을 조건으로 보므로
  // 마지막 문장이 결과를 채우는 순간 조건이 닫혀, 같은 호출이 반복돼도 환불은 한 번뿐
  const unwritten =
    'EXISTS (SELECT 1 FROM analyses WHERE user_id = ? AND request_id = ? AND claim = ? AND result IS NULL)';
  const results = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ledger (user_id, delta, reason, ref, created_at) SELECT ?, ?, 'analyze_partial_refund', ?, ? WHERE ? > 0 AND ${unwritten}`,
    ).bind(userId, refund, requestId, now, refund, userId, requestId, claim),
    env.DB.prepare(
      `UPDATE users SET balance = balance + ? WHERE id = ? AND ? > 0 AND ${unwritten}`,
    ).bind(refund, userId, refund, userId, requestId, claim),
    env.DB.prepare(
      'UPDATE analyses SET result = ?, cost = cost - ? ' +
        'WHERE user_id = ? AND request_id = ? AND claim = ? AND result IS NULL',
    ).bind(result, refund, userId, requestId, claim),
  ]);
  return results.at(-1)?.meta.changes === 1;
}

/// 분석이 실패했을 때 뺀 코인을 전부 돌려주고 기록을 지움. 선점을 쥔 경우에만 적용되어
/// 같은 id의 다른 요청이 몇 번 실패해도 환불은 한 번뿐. 환불했으면 true.
export async function abandonAnalysis(
  env: Env,
  userId: string,
  requestId: string,
  claim: string,
  now = Date.now(),
): Promise<boolean> {
  const results = await env.DB.batch(
    refundStatements(env, userId, 'request_id = ? AND claim = ?', [requestId, claim], now),
  );
  return results.at(-1)?.meta.changes === 1;
}
