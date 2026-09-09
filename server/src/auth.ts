// 익명 사용자 식별. 로그인 없이 기기마다 id와 토큰을 발급하고, 기기를 옮길 때 쓰는 복구 코드를 함께 줌.
// 토큰과 복구 코드는 해시만 저장해 DB가 유출돼도 그대로 쓰이지 않게 함.

import type { Env } from './env.js';

/// 사람이 눈으로 읽고 옮겨 적을 수 있는 문자만 씀. 0/O, 1/I 같은 혼동 쌍을 뺌.
const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 한 IP가 하루에 쓸 수 있는 횟수. 한 집에서 여러 기기를 쓰는 경우를 넉넉히 덮되
/// 사용자 행을 무한히 찍어 내거나 복구 코드를 두들기지는 못하게 하는 선.
const ATTEMPTS_PER_DAY = 20;

export interface User {
  id: string;
  balance: number;
}

/// 암호학적 난수를 hex 문자열로. 토큰과 사용자 id에 씀.
function randomHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return [...buf].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/// 사람이 받아 적는 복구 코드. XXXX-XXXX-XXXX 형태로 약 60비트.
function randomRecoveryCode(): string {
  const buf = new Uint8Array(12);
  crypto.getRandomValues(buf);
  const chars = [...buf].map((b) => RECOVERY_ALPHABET[b % RECOVERY_ALPHABET.length]);
  return [chars.slice(0, 4), chars.slice(4, 8), chars.slice(8, 12)]
    .map((g) => g.join(''))
    .join('-');
}

/// 비밀값을 SHA-256 hex로. 토큰·복구 코드는 이 값만 저장함.
export async function hash(secret: string): Promise<string> {
  const data = new TextEncoder().encode(secret);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/// 요청한 IP의 오늘 시도 수를 하나 올리고, 한도를 넘었으면 false.
/// scope로 등록과 복구를 따로 셈. 둘 다 인증 없이 서버 상태를 바꾸는 경로임.
/// 해시는 IP를 목록에서 가리는 정도이지 되돌리기를 막지는 못함. 속도 제한 용도로만 씀.
export async function claimRegistrationSlot(
  env: Env,
  request: Request,
  scope = 'register',
): Promise<boolean> {
  const ip = request.headers.get('CF-Connecting-IP');
  // IP를 알 수 없으면(로컬 개발 등) 제한하지 않음
  if (!ip) return true;

  const day = Math.floor(Date.now() / 86_400_000);
  const ipHash = await hash(`${scope}:${ip}`);
  const [, counted] = await env.DB.batch<{ count: number }>([
    // 지난 기록은 쓸모가 없고 그대로 두면 무한히 쌓임
    env.DB.prepare('DELETE FROM registrations WHERE day < ?').bind(day - 1),
    env.DB.prepare(
      'INSERT INTO registrations (ip_hash, day, count) VALUES (?, ?, 1) ' +
        'ON CONFLICT(ip_hash, day) DO UPDATE SET count = count + 1 RETURNING count',
    ).bind(ipHash, day),
  ]);

  return (counted.results[0]?.count ?? 1) <= ATTEMPTS_PER_DAY;
}

/// 새 익명 사용자를 만들고 토큰과 복구 코드를 돌려줌. 복구 코드는 이때 한 번만 평문으로 나감.
export async function registerDevice(env: Env) {
  const id = randomHex(16);
  const token = randomHex(32);
  const recoveryCode = randomRecoveryCode();

  await env.DB.prepare(
    'INSERT INTO users (id, token_hash, recovery_hash, balance, created_at) VALUES (?, ?, ?, 0, ?)',
  )
    .bind(id, await hash(token), await hash(recoveryCode), Date.now())
    .run();

  return { userId: id, token, recoveryCode, balance: 0 };
}

/// 복구 코드로 기존 사용자를 새 기기에 붙임. 옛 토큰은 무효가 되어 기기 하나만 남음.
export async function restoreDevice(env: Env, recoveryCode: string) {
  const row = await env.DB.prepare('SELECT id, balance FROM users WHERE recovery_hash = ?')
    .bind(await hash(recoveryCode.trim().toUpperCase()))
    .first<{ id: string; balance: number }>();
  if (!row) return null;

  const token = randomHex(32);
  await env.DB.prepare('UPDATE users SET token_hash = ? WHERE id = ?')
    .bind(await hash(token), row.id)
    .run();

  return { userId: row.id, token, balance: row.balance };
}

/// 복구 코드를 새로 발급하고 해시를 갈아 끼움. 이전 코드는 이 순간부터 통하지 않음.
/// 서버가 해시만 들고 있어 이미 발급한 코드를 다시 보여 줄 방법이 없으므로 재발급으로 대신함.
export async function reissueRecoveryCode(env: Env, userId: string): Promise<string> {
  const recoveryCode = randomRecoveryCode();
  await env.DB.prepare('UPDATE users SET recovery_hash = ? WHERE id = ?')
    .bind(await hash(recoveryCode), userId)
    .run();
  return recoveryCode;
}

/// Authorization 헤더의 토큰으로 사용자를 찾음. 없으면 null.
export async function authenticate(env: Env, request: Request): Promise<User | null> {
  const header = request.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) return null;

  const row = await env.DB.prepare('SELECT id, balance FROM users WHERE token_hash = ?')
    .bind(await hash(token))
    .first<{ id: string; balance: number }>();
  return row ? { id: row.id, balance: row.balance } : null;
}
