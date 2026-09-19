// 분석 멱등키 검증. 같은 requestId가 겹쳐 와도 차감·환불이 한 번씩만 일어나야
// 코인 원장을 서버에만 둔 의미가 있음. 동시 요청은 호출 순서를 섞어 흉내 냄.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  abandonAnalysis,
  ANALYSIS_LEASE_MS,
  claimAnalysis,
  completeAnalysis,
  refundStaleAnalyses,
  staleRefundStatements,
} from '../src/analyses.ts';
import { addUser, fakeD1, money } from './fake_d1.ts';

/// 잔액 8인 사용자와 D1 대역을 만듦.
function setup(balance = 8) {
  const DB = fakeD1();
  addUser(DB, 'u', balance);
  return { env: { DB } as never, DB };
}

test('처음 온 요청만 선점하고 한 번만 뺌', async () => {
  const { env, DB } = setup();
  const a = await claimAnalysis(env, 'u', 'req-1', '0,1', 8, 1000);
  const b = await claimAnalysis(env, 'u', 'req-1', '0,1', 8, 1001);
  assert.equal(a.kind, 'claimed');
  assert.equal(b.kind, 'running');
  assert.deepEqual(money(DB, 'u'), { balance: 0, ledger: -8 });
});

test('같은 id로 다른 쪽을 보내면 공짜로 분석하지 않고 거절함', async () => {
  const { env } = setup();
  await claimAnalysis(env, 'u', 'req-1', '0,1', 8, 1000);
  assert.equal((await claimAnalysis(env, 'u', 'req-1', '2,3', 8, 1001)).kind, 'mismatch');
});

test('실패 환불은 선점한 요청만 한 번 받음', async () => {
  const { env, DB } = setup();
  const a = await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000);
  assert.equal(a.kind, 'claimed');
  if (a.kind !== 'claimed') return;
  // 같은 id의 다른 요청은 선점이 없어 분석도 환불도 못 함
  assert.equal(await abandonAnalysis(env, 'u', 'req-1', 'someone-else', 1001), false);
  assert.equal(await abandonAnalysis(env, 'u', 'req-1', a.claim, 1002), true);
  assert.equal(await abandonAnalysis(env, 'u', 'req-1', a.claim, 1003), false);
  assert.deepEqual(money(DB, 'u'), { balance: 8, ledger: 8 - 8 });
});

test('끝난 분석은 다시 빼지 않고 저장된 결과를 줌', async () => {
  const { env, DB } = setup();
  const a = await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000);
  if (a.kind !== 'claimed') assert.fail();
  assert.equal(await completeAnalysis(env, 'u', 'req-1', a.claim, '{"pages":[]}', 0, 1001), true);
  const again = await claimAnalysis(env, 'u', 'req-1', '0', 8, 1002);
  assert.deepEqual(again, { kind: 'done', cost: 8, result: '{"pages":[]}' });
  assert.deepEqual(money(DB, 'u'), { balance: 0, ledger: -8 });
});

test('모델이 빠뜨린 쪽 몫은 한 번만 돌려주고 저장된 비용도 줄어듦', async () => {
  const { env, DB } = setup();
  const a = await claimAnalysis(env, 'u', 'req-1', '0,1,2,3', 8, 1000);
  if (a.kind !== 'claimed') assert.fail();
  assert.equal(await completeAnalysis(env, 'u', 'req-1', a.claim, '{}', 2, 1001), true);
  assert.equal(await completeAnalysis(env, 'u', 'req-1', a.claim, '{}', 2, 1002), false);
  assert.deepEqual(money(DB, 'u'), { balance: 2, ledger: -8 + 2 });
  const again = await claimAnalysis(env, 'u', 'req-1', '0,1,2,3', 8, 1003);
  assert.equal(again.kind === 'done' && again.cost, 6);
});

test('기한이 지나도록 결과가 없으면 환불하고, 늦게 끝난 원래 요청은 결과를 쓰지 못함', async () => {
  const { env, DB } = setup();
  const a = await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000);
  if (a.kind !== 'claimed') assert.fail();
  await refundStaleAnalyses(env, 'u', 1000 + ANALYSIS_LEASE_MS);
  assert.deepEqual(money(DB, 'u'), { balance: 8, ledger: 0 });
  const late = 1000 + ANALYSIS_LEASE_MS + 1;
  assert.equal(await completeAnalysis(env, 'u', 'req-1', a.claim, '{}', 0, late), false);
  assert.equal(await abandonAnalysis(env, 'u', 'req-1', a.claim), false);
  assert.deepEqual(money(DB, 'u'), { balance: 8, ledger: 0 });
});

test('버려진 요청을 같은 id로 다시 보내면 환불 뒤 새로 한 번만 뺌', async () => {
  const { env, DB } = setup();
  await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000);
  const retry = await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000 + ANALYSIS_LEASE_MS);
  assert.equal(retry.kind, 'claimed');
  assert.deepEqual(money(DB, 'u'), { balance: 0, ledger: -8 });
});

test('잔액이 모자라면 선점하지 않고 원장도 건드리지 않음', async () => {
  const { env, DB } = setup(3);
  assert.deepEqual(await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000), {
    kind: 'insufficient',
    balance: 3,
  });
  assert.deepEqual(money(DB, 'u'), { balance: 3, ledger: 0 });
  assert.equal((await claimAnalysis(env, 'u', 'req-2', '0', 3, 1001)).kind, 'claimed');
});

test('requestId는 사용자마다 따로 셈', async () => {
  const { env, DB } = setup();
  addUser(DB, 'v', 8);
  assert.equal((await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000)).kind, 'claimed');
  assert.equal((await claimAnalysis(env, 'v', 'req-1', '0', 8, 1000)).kind, 'claimed');
});

test('기한 지난 분석이 없으면 잔액 조회의 환불 정리가 아무 행도 쓰지 않음', async () => {
  const { env, DB } = setup();
  await claimAnalysis(env, 'u', 'req-1', '0', 8, 1000);
  const results = await DB.batch(staleRefundStatements(env, 'u', 1001) as never);
  const written = results.reduce((n, r) => n + r.meta.changes, 0);
  assert.equal(written, 0);
  assert.deepEqual(money(DB, 'u'), { balance: 0, ledger: -8 });
});
