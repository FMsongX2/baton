// 인앱 결제 영수증 검증. 스토어에 직접 물어봐야 하며, 검증 없이 적립하면 위조 영수증으로 코인을 무한히 만들 수 있음.
// 아직 스토어 자격증명을 붙이지 않았으므로 기본은 거부. 붙인 뒤 verify 안을 채우고 설정을 풀면 됨.

import { blocksUnverifiedPurchases, type Env } from './env.js';

/// 상품 id별 지급 코인. 스토어에 등록할 소모성 상품과 짝을 맞춰야 함.
export const COIN_PACKS: Record<string, number> = {
  baton_coins_10: 10,
  baton_coins_60: 60,
  baton_coins_150: 150,
};

export interface VerifyResult {
  verified: boolean;
  coins: number;
  reason?: string;
}

/// 영수증을 스토어에 확인함.
/// 지금은 자격증명이 없어 항상 미검증으로 돌려주며, 설정이 막고 있으면 적립도 거부됨.
export async function verifyPurchase(
  env: Env,
  platform: string,
  productId: string,
  _purchaseToken: string,
): Promise<VerifyResult> {
  const coins = COIN_PACKS[productId];
  if (!coins) return { verified: false, coins: 0, reason: '알 수 없는 상품' };

  // TODO: Google Play Developer API(purchases.products.get)와
  //       App Store Server API(inApps/v1/transactions)로 실제 확인.
  //       둘 다 서비스 계정 키가 필요하므로 wrangler secret으로 넣고 여기서 씀.
  if (blocksUnverifiedPurchases(env)) {
    return {
      verified: false,
      coins,
      reason: `${platform} 영수증 검증이 아직 설정되지 않음`,
    };
  }
  return { verified: true, coins };
}
