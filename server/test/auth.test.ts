// 복구 코드 검증. 대시·공백을 빼고 넣어도 같은 코드로 찾아야 하고,
// 재발급 응답이 유실돼도 확인 전까지 이전 코드가 살아 있어야 코인을 잃지 않음.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  confirmRecoveryCode,
  normalizeRecoveryCode,
  registerDevice,
  reissueRecoveryCode,
  restoreDevice,
} from '../src/auth.ts';
import { fakeD1 } from './fake_d1.ts';

test('대시·공백·소문자로 넣어도 발급 모양으로 맞춤', () => {
  assert.equal(normalizeRecoveryCode('ABCD-EFGH-JKLM'), 'ABCD-EFGH-JKLM');
  assert.equal(normalizeRecoveryCode('abcdefghjklm'), 'ABCD-EFGH-JKLM');
  assert.equal(normalizeRecoveryCode(' abcd efgh  jklm '), 'ABCD-EFGH-JKLM');
});

test('12자가 아니거나 발급에 없는 문자면 null', () => {
  assert.equal(normalizeRecoveryCode('ABCD-EFGH-JKL'), null);
  assert.equal(normalizeRecoveryCode('ABCD-EFGH-JKLMN'), null);
  // 0·O·1·I는 발급 문자에서 뺐으므로 맞을 수 없음
  assert.equal(normalizeRecoveryCode('ABCD-EFGH-JKL0'), null);
});

test('재발급한 코드는 확인 전까지 쓰이지 않고 이전 코드가 통함', async () => {
  const env = { DB: fakeD1() } as never;
  const first = await registerDevice(env);
  const next = await reissueRecoveryCode(env, first.userId);

  // 응답이 유실돼 사용자가 새 코드를 못 받은 상황. 이전 코드가 살아 있어야 함
  assert.notEqual(await restoreDevice(env, first.recoveryCode), null);
  assert.equal(await restoreDevice(env, next), null);

  assert.equal(await confirmRecoveryCode(env, first.userId, next), true);
  // 확인 응답이 유실돼 다시 보내도 같은 결과
  assert.equal(await confirmRecoveryCode(env, first.userId, next), true);
  assert.equal(await restoreDevice(env, first.recoveryCode), null);
  assert.notEqual(await restoreDevice(env, next), null);
});

test('그사이 다른 코드가 발급됐으면 앞 코드는 확인되지 않음', async () => {
  const env = { DB: fakeD1() } as never;
  const user = await registerDevice(env);
  const a = await reissueRecoveryCode(env, user.userId);
  const b = await reissueRecoveryCode(env, user.userId);
  assert.equal(await confirmRecoveryCode(env, user.userId, a), false);
  assert.equal(await confirmRecoveryCode(env, user.userId, b), true);
});
