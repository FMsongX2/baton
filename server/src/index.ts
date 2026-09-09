// 앱이 부르는 HTTP 진입점. 코인 원장과 Claude 키를 서버에만 두기 위해 존재함.
// 분석은 코인을 먼저 빼고 실패하면 되돌려 준다. 먼저 빼야 동시에 눌러도 잔액이 무너지지 않음.

import * as z from 'zod/v4';
import { analyzeScore, type PageImage } from './analyze.js';
import {
  authenticate,
  claimRegistrationSlot,
  registerDevice,
  reissueRecoveryCode,
  restoreDevice,
} from './auth.js';
import { balanceOf, grant, grantStatements, spend } from './coins.js';
import { coinsPerPage, type Env } from './env.js';
import { COIN_PACKS, verifyPurchase } from './receipts.js';

/// 한 번에 분석할 수 있는 최대 쪽수.
/// 1400px PNG 한 장이 base64로 1~3MB라 크게 잡으면 요청 본문과 메모리 한도를 먼저 넘김.
/// 모델에 한 번에 넣는 장수(analyze.ts의 PAGES_PER_REQUEST)와 맞춰 둠.
const MAX_PAGES_PER_CALL = 8;

/// 이미지 한 장의 base64 길이 상한. 1400px PNG가 보통 1~3MB라 넉넉히 잡되
/// 본문 하나가 워커 메모리를 통째로 먹지 않게 막음.
const MAX_IMAGE_BASE64 = 12_000_000;

/// 분석 요청 본문. 인증된 사용자라도 잘못된 모양이 코인 차감까지 흘러가면 안 되므로
/// spend 앞에서 전부 검사함.
const AnalyzeRequest = z.object({
  requestId: z.string().min(8).max(128),
  pages: z
    .array(
      z.object({
        index: z.number().int().min(0).max(9999),
        mediaType: z.enum(['image/png', 'image/jpeg']),
        base64: z.string().min(1).max(MAX_IMAGE_BASE64),
      }),
    )
    .min(1)
    .max(MAX_PAGES_PER_CALL),
});

/// JSON 응답을 만듦.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/// 오류 응답을 만듦. 앱이 사용자에게 그대로 보여줄 수 있는 문구만 담음.
function fail(message: string, status: number): Response {
  return json({ error: message }, status);
}

/// 본문을 JSON으로 읽음. 깨져 있으면 400으로 떨어뜨림. 최상위 catch에 맡기면 500이 나감.
async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    throw new BadRequest('요청 형식이 잘못됨');
  }
}

/// 사용자 입력이 잘못된 경우. 400으로 바꿔 내보냄.
class BadRequest extends Error {}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (request.method === 'POST' && path === '/v1/device/register') {
        if (!(await claimRegistrationSlot(env, request))) {
          return fail('오늘 이 회선에서 만들 수 있는 기기 수를 넘음', 429);
        }
        return json(await registerDevice(env));
      }

      if (request.method === 'POST' && path === '/v1/device/restore') {
        // 인증 없이 서버 상태를 바꾸는 유일한 경로라 등록과 같은 회선 제한을 검
        if (!(await claimRegistrationSlot(env, request, 'restore'))) {
          return fail('오늘 이 회선에서 시도할 수 있는 횟수를 넘음', 429);
        }
        const body = (await readJson(request)) as { recoveryCode?: unknown };
        if (typeof body?.recoveryCode !== 'string' || !body.recoveryCode) {
          return fail('복구 코드가 없음', 400);
        }
        const restored = await restoreDevice(env, body.recoveryCode);
        if (!restored) return fail('복구 코드를 찾을 수 없음', 404);
        return json(restored);
      }

      if (request.method === 'GET' && path === '/v1/pricing') {
        return json({
          coinsPerPage: coinsPerPage(env),
          packs: Object.entries(COIN_PACKS).map(([productId, coins]) => ({ productId, coins })),
          maxPagesPerCall: MAX_PAGES_PER_CALL,
        });
      }

      const user = await authenticate(env, request);
      if (!user) return fail('인증이 필요함', 401);

      if (request.method === 'POST' && path === '/v1/device/recovery') {
        return json({ recoveryCode: await reissueRecoveryCode(env, user.id) });
      }

      if (request.method === 'GET' && path === '/v1/balance') {
        return json({ balance: (await balanceOf(env, user.id)) ?? 0 });
      }

      if (request.method === 'POST' && path === '/v1/purchase') {
        return await handlePurchase(env, request, user.id);
      }

      if (request.method === 'POST' && path === '/v1/analyze') {
        return await handleAnalyze(env, request, user.id);
      }

      return fail('없는 경로', 404);
    } catch (e) {
      if (e instanceof BadRequest) return fail(e.message, 400);
      console.error(e);
      return fail('서버 오류', 500);
    }
  },
} satisfies ExportedHandler<Env>;

/// 영수증을 확인하고 코인을 넣음. 같은 영수증이 두 번 와도 유일키에 걸려 한 번만 적립됨.
async function handlePurchase(env: Env, request: Request, userId: string): Promise<Response> {
  const body = (await readJson(request)) as {
    platform?: unknown;
    productId?: unknown;
    purchaseToken?: unknown;
  };
  const { platform, productId, purchaseToken } = body ?? {};
  if (
    typeof platform !== 'string' ||
    typeof productId !== 'string' ||
    typeof purchaseToken !== 'string' ||
    !platform ||
    !productId ||
    !purchaseToken
  ) {
    return fail('구매 정보가 모자람', 400);
  }

  const result = await verifyPurchase(env, platform, productId, purchaseToken);
  if (!result.verified) {
    return fail(result.reason ?? '영수증을 확인하지 못함', 402);
  }

  if (await isRedeemed(env, purchaseToken)) {
    return json({ balance: (await balanceOf(env, userId)) ?? 0, granted: 0, duplicate: true });
  }

  // 영수증 기록과 적립을 한 batch로 묶음. 따로 하면 사이에서 끊겼을 때
  // 영수증만 남아 재전송이 중복으로 막히고 코인은 영영 들어가지 않음
  try {
    await env.DB.batch([
      env.DB.prepare(
        'INSERT INTO purchases (user_id, platform, product_id, purchase_token, coins, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      ).bind(userId, platform, productId, purchaseToken, result.coins, Date.now()),
      ...grantStatements(env, userId, result.coins, 'purchase', purchaseToken),
    ]);
  } catch (e) {
    // 유일키 충돌이면 그 사이 다른 요청이 적립을 마친 것. 그 밖의 실패는 실패로 알려야 함.
    // 전부 중복으로 처리하면 앱이 스토어 구매를 완료 처리해 재전송으로 되찾을 길이 사라짐
    if (await isRedeemed(env, purchaseToken)) {
      return json({ balance: (await balanceOf(env, userId)) ?? 0, granted: 0, duplicate: true });
    }
    console.error(e);
    return fail('코인을 넣지 못함. 잠시 뒤 다시 시도', 503);
  }

  return json({
    balance: (await balanceOf(env, userId)) ?? 0,
    granted: result.coins,
    duplicate: false,
  });
}

/// 이 영수증이 이미 적립됐는지.
async function isRedeemed(env: Env, purchaseToken: string): Promise<boolean> {
  const row = await env.DB.prepare('SELECT 1 AS ok FROM purchases WHERE purchase_token = ?')
    .bind(purchaseToken)
    .first<{ ok: number }>();
  return row !== null;
}

/// 코인을 먼저 빼고 분석함. 분석이 실패하면 뺀 만큼 그대로 되돌려 줌.
async function handleAnalyze(env: Env, request: Request, userId: string): Promise<Response> {
  const parsed = AnalyzeRequest.safeParse(await readJson(request));
  if (!parsed.success) {
    return fail(`분석 요청이 잘못됨: ${parsed.error.issues[0]?.message ?? ''}`, 400);
  }
  const { requestId, pages } = parsed.data;

  // 같은 요청이 다시 오면 코인을 또 빼지 않음. 응답이 도중에 끊겨도 결과를 되찾을 수 있어야 함
  const prior = await env.DB.prepare(
    'SELECT cost, result FROM analyses WHERE request_id = ? AND user_id = ?',
  )
    .bind(requestId, userId)
    .first<{ cost: number; result: string | null }>();

  let cost: number;
  if (prior) {
    if (prior.result) {
      const balance = (await balanceOf(env, userId)) ?? 0;
      return json({ ...JSON.parse(prior.result), coinsSpent: prior.cost, balance });
    }
    // 앞서 코인만 빠지고 끝난 요청. 다시 빼지 않고 분석만 이어서 함
    cost = prior.cost;
  } else {
    cost = pages.length * coinsPerPage(env);
    const afterSpend = await spend(env, userId, cost, 'analyze', requestId);
    if (afterSpend === null) {
      const balance = (await balanceOf(env, userId)) ?? 0;
      return json({ error: '코인이 모자람', needed: cost, balance }, 402);
    }
    await env.DB.prepare(
      'INSERT INTO analyses (request_id, user_id, cost, result, created_at) VALUES (?, ?, ?, NULL, ?)',
    )
      .bind(requestId, userId, cost, Date.now())
      .run();
  }

  try {
    const analysis = await analyzeScore(env, pages as PageImage[]);
    await env.DB.prepare('UPDATE analyses SET result = ? WHERE request_id = ?')
      .bind(JSON.stringify(analysis), requestId)
      .run();
    const balance = (await balanceOf(env, userId)) ?? 0;
    return json({ ...analysis, coinsSpent: cost, balance });
  } catch (e) {
    // 되돌려 주고 기록도 지움. 남겨 두면 재시도가 "코인은 이미 뺐다"고 오해함
    const balance = await grant(env, userId, cost, 'analyze_refund', requestId);
    await env.DB.prepare('DELETE FROM analyses WHERE request_id = ?').bind(requestId).run();
    console.error(e);
    return json({ error: '분석에 실패해 코인을 돌려줌', balance }, 502);
  }
}
