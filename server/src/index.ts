// 앱이 부르는 HTTP 진입점. 코인 원장과 OpenAI 키를 서버에만 두기 위해 존재함.
// 분석은 requestId를 선점하며 코인을 먼저 빼고, 실패하면 선점한 요청만 한 번 되돌려 줌(analyses.ts).

import * as z from 'zod/v4';
import { analyzeScore, type PageImage } from './analyze.js';
import {
  abandonAnalysis,
  claimAnalysis,
  completeAnalysis,
  refundStaleAnalyses,
} from './analyses.js';
import {
  authenticate,
  claimRegistrationSlot,
  confirmRecoveryCode,
  normalizeRecoveryCode,
  registerDevice,
  reissueRecoveryCode,
  restoreDevice,
} from './auth.js';
import { balanceOf, grantStatements } from './coins.js';
import { coinsPerPage, type Env } from './env.js';
import { COIN_PACKS, verifyPurchase } from './receipts.js';

/// 한 번에 분석할 수 있는 최대 쪽수.
/// 1400px PNG 한 장이 base64로 1~3MB라 크게 잡으면 요청 본문과 메모리 한도를 먼저 넘김.
/// 모델에 한 번에 넣는 장수(analyze.ts의 PAGES_PER_REQUEST)와 맞춰 둠.
const MAX_PAGES_PER_CALL = 8;

/// 이미지 한 장의 base64 길이 상한. 1400px PNG가 보통 1~3MB라 넉넉히 잡되
/// 본문 하나가 워커 메모리를 통째로 먹지 않게 막음.
const MAX_IMAGE_BASE64 = 12_000_000;

/// 형식별 파일 첫 바이트. 깨진 본문을 코인 차감과 모델 호출 전에 걸러 냄.
const IMAGE_SIGNATURES: Record<'image/png' | 'image/jpeg', number[]> = {
  'image/png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  'image/jpeg': [0xff, 0xd8, 0xff],
};

/// base64가 올바른 문자·길이이고, 풀면 선언한 형식의 서명으로 시작하는지.
function isImage(page: { mediaType: 'image/png' | 'image/jpeg'; base64: string }): boolean {
  if (page.base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(page.base64)) return false;
  const head = atob(page.base64.slice(0, 12));
  return IMAGE_SIGNATURES[page.mediaType].every((b, i) => head.charCodeAt(i) === b);
}

/// 분석 요청 본문. 인증된 사용자라도 잘못된 모양이 코인 차감까지 흘러가면 안 되므로
/// 선점 앞에서 전부 검사함.
const AnalyzeRequest = z.object({
  requestId: z.string().min(8).max(128),
  pages: z
    .array(
      z
        .object({
          index: z.number().int().min(0).max(9999),
          mediaType: z.enum(['image/png', 'image/jpeg']),
          base64: z.string().min(1).max(MAX_IMAGE_BASE64),
        })
        .refine(isImage, '이미지가 깨짐'),
    )
    .min(1)
    .max(MAX_PAGES_PER_CALL),
});

/// 복구 코드를 담은 본문을 읽어 발급 모양으로 맞춤. 모양이 틀리면 400으로 떨어뜨림.
async function readRecoveryCode(request: Request): Promise<string> {
  const body = (await readJson(request)) as { recoveryCode?: unknown };
  const code =
    typeof body?.recoveryCode === 'string' ? normalizeRecoveryCode(body.recoveryCode) : null;
  if (!code) throw new BadRequest('복구 코드는 XXXX-XXXX-XXXX 모양의 12자임');
  return code;
}

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
        // 모양이 틀린 입력은 맞을 수 없으므로 한도를 쓰기 전에 거름
        const code = await readRecoveryCode(request);
        // 인증 없이 서버 상태를 바꾸는 유일한 경로라 등록과 같은 회선 제한을 검
        if (!(await claimRegistrationSlot(env, request, 'restore'))) {
          return fail('오늘 이 회선에서 시도할 수 있는 횟수를 넘음', 429);
        }
        const restored = await restoreDevice(env, code);
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

      if (request.method === 'POST' && path === '/v1/device/recovery/confirm') {
        if (!(await confirmRecoveryCode(env, user.id, await readRecoveryCode(request)))) {
          return fail('그사이 다른 코드가 발급됨. 복구 코드를 다시 받음', 409);
        }
        return json({ confirmed: true });
      }

      if (request.method === 'GET' && path === '/v1/balance') {
        // 앱이 끝내 다시 보내지 않은 분석도 여기서 돌려받게 함
        await refundStaleAnalyses(env, user.id);
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

/// requestId를 선점하며 코인을 빼고 분석함. 같은 id가 다시 오면 차감 없이 저장된 결과를 주거나
/// 진행 중(409)이라고 알림. 분석이 실패하면 선점한 요청만 전액 되돌려 주고,
/// 모델이 빠뜨린 쪽은 그 몫만 되돌려 줌.
async function handleAnalyze(env: Env, request: Request, userId: string): Promise<Response> {
  const parsed = AnalyzeRequest.safeParse(await readJson(request));
  if (!parsed.success) {
    return fail(`분석 요청이 잘못됨: ${parsed.error.issues[0]?.message ?? ''}`, 400);
  }
  const { requestId, pages } = parsed.data;
  const cost = pages.length * coinsPerPage(env);

  const claim = await claimAnalysis(
    env,
    userId,
    requestId,
    pages.map((p) => p.index).join(','),
    cost,
  );
  switch (claim.kind) {
    case 'insufficient':
      return json({ error: '코인이 모자람', needed: cost, balance: claim.balance }, 402);
    case 'mismatch':
      return fail('같은 요청 id로 다른 쪽을 보냄', 422);
    case 'running':
      return json({ error: '같은 분석이 아직 진행 중. 잠시 뒤 다시 시도', pending: true }, 409);
    case 'done': {
      const balance = (await balanceOf(env, userId)) ?? 0;
      return json({ ...JSON.parse(claim.result), coinsSpent: claim.cost, balance });
    }
  }

  let analysis;
  try {
    analysis = await analyzeScore(env, pages as PageImage[]);
  } catch (e) {
    console.error(e);
    const refunded = await abandonAnalysis(env, userId, requestId, claim.claim);
    const balance = (await balanceOf(env, userId)) ?? 0;
    return json({ error: refunded ? '분석에 실패해 코인을 돌려줌' : '분석에 실패함', balance }, 502);
  }

  // 요청한 쪽 중 결과가 없는 만큼 돌려줌. analyzeScore가 요청 밖·중복 쪽을 이미 걸러 냄
  const missing = pages.length - analysis.pages.length;
  const refund = Math.round((claim.cost * missing) / pages.length);
  const result = JSON.stringify(analysis);
  if (!(await completeAnalysis(env, userId, requestId, claim.claim, result, refund))) {
    // 기한이 지나 환불되고 선점을 잃음. 결과를 공짜로 내주지 않고 다시 보내게 함
    return json({ error: '분석이 너무 오래 걸려 취소됨. 다시 시도', pending: true }, 409);
  }
  const balance = (await balanceOf(env, userId)) ?? 0;
  return json({ ...analysis, coinsSpent: claim.cost - refund, balance });
}
