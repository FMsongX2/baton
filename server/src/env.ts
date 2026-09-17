// Worker에 주입되는 바인딩과 설정. 비밀값은 wrangler secret으로만 넣고 저장소에 두지 않음.

export interface Env {
  DB: D1Database;
  OPENAI_API_KEY: string;
  OPENAI_MODEL: string;
  COINS_PER_PAGE: string;
  BLOCK_UNVERIFIED_PURCHASES: string;
}

/// 악보 분석에 쓸 모델. 설정이 비면 기본값을 씀.
export function analysisModel(env: Env): string {
  const m = env.OPENAI_MODEL?.trim();
  return m ? m : 'gpt-5.6-luna';
}

/// 페이지 한 장당 소모 코인. 설정이 비었거나 이상하면 1로 둠.
export function coinsPerPage(env: Env): number {
  const n = Number.parseInt(env.COINS_PER_PAGE ?? '1', 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}

/// 영수증 검증을 아직 붙이지 않은 동안 구매 적립을 막을지.
export function blocksUnverifiedPurchases(env: Env): boolean {
  return (env.BLOCK_UNVERIFIED_PURCHASES ?? '1') !== '0';
}
