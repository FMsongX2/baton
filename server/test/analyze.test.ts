// 모델 호출 한도 검증. 한도나 시간 초과로 끊긴 호출을 다시 보내면 토큰을 두 번 쓰고,
// 한도가 선점 기한을 넘으면 살아 있는 분석이 환불됨. 모델 서버는 fetch 대역으로 흉내 냄.

import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { afterEach, test } from 'node:test';

registerHooks({
  /// 소스는 번들러 규칙대로 './env.js'처럼 적음. 없으면 같은 이름의 .ts로 풀어 이 파일에서만 불러옴.
  resolve(specifier, context, next) {
    if (!specifier.startsWith('.') || !specifier.endsWith('.js')) return next(specifier, context);
    try {
      return next(specifier, context);
    } catch {
      return next(`${specifier.slice(0, -3)}.ts`, context);
    }
  },
});

const { ANALYSIS_BUDGET_MS, analyzeScore } = await import('../src/analyze.ts');
const { ANALYSIS_LEASE_MS } = await import('../src/analyses.ts');

const env = { OPENAI_API_KEY: 'k', OPENAI_MODEL: 'm' } as never;
const page = { index: 0, mediaType: 'image/png' as const, base64: 'AAAA' };
const realFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = realFetch;
});

/// 모델 서버 대역을 걸고 받은 요청 수를 셈. 응답을 정하지 않은 호출은 끊길 때까지 답하지 않음.
function fakeModel(replies: (() => Response)[]) {
  const calls = { count: 0 };
  globalThis.fetch = (async (_url: unknown, init?: RequestInit) => {
    const reply = replies[calls.count++];
    if (reply) return reply();
    return new Promise<Response>((_, reject) => {
      init?.signal?.addEventListener('abort', () =>
        reject(new DOMException('aborted', 'AbortError')),
      );
    });
  }) as typeof fetch;
  return calls;
}

/// 1쪽 7마디로 읽었다는 모델 응답.
function parsedReply(): Response {
  const analysis = {
    pages: [{ page: 1, bars: 7, confidence: 'high' }],
    bpm: null,
    bpmUnit: null,
    bpmSource: 'none',
    timeSigNum: null,
    timeSigDen: null,
  };
  const body = {
    id: 'resp_1',
    object: 'response',
    status: 'completed',
    output: [
      {
        type: 'message',
        id: 'msg_1',
        role: 'assistant',
        status: 'completed',
        content: [{ type: 'output_text', text: JSON.stringify(analysis), annotations: [] }],
      },
    ],
  };
  return new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });
}

test('한도에 걸린 모델 호출은 다시 보내지 않고 실패함', async () => {
  const calls = fakeModel([]);
  await assert.rejects(analyzeScore(env, [page], 50));
  assert.equal(calls.count, 1);
});

test('모델 쪽이 시간 초과로 답하면 다시 보내지 않고 실패함', async () => {
  for (const status of [408, 504, 524]) {
    const calls = fakeModel([
      () => new Response('{}', { status, headers: { 'retry-after-ms': '0' } }),
      parsedReply,
    ]);
    await assert.rejects(analyzeScore(env, [page], 5_000));
    assert.equal(calls.count, 1, `${status}`);
  }
});

test('모델이 5xx로 거절하면 한도 안에서 한 번 더 보냄', async () => {
  const calls = fakeModel([
    () => new Response('{}', { status: 500, headers: { 'retry-after-ms': '0' } }),
    parsedReply,
  ]);
  const result = await analyzeScore(env, [page], 5_000);
  assert.equal(calls.count, 2);
  assert.deepEqual(result.pages, [{ page: 1, bars: 7, confidence: 'high' }]);
});

test('모델 호출 한도는 선점 기한 안에 결과를 기록할 몫을 남김', () => {
  assert.ok(ANALYSIS_BUDGET_MS + 30_000 <= ANALYSIS_LEASE_MS);
});
