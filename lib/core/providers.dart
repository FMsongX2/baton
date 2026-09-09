// 앱 전역에 하나만 있어야 하는 것들의 주입 지점. DB 연결과 리포지토리가 여기에 묶임.
// 화면 상태는 각 화면이 들고 있고 여기에 올리지 않음.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/purchases.dart';
import '../cloud/api_client.dart';
import '../cloud/coin_wallet.dart';
import '../library/library_repo.dart';
import '../metronome/audio_service.dart';
import '../score/ai_analysis.dart';
import '../score/score_repo.dart';
import 'db/database.dart';
import 'db/settings_repo.dart';

/// DB 연결. 앱 수명 동안 하나만 열어 둠.
final dbProvider = Provider<BatonDatabase>((ref) {
  final db = BatonDatabase();
  ref.onDispose(db.close);
  return db;
});

final libraryRepoProvider = Provider((ref) => LibraryRepo(ref.watch(dbProvider)));

final scoreRepoProvider = Provider((ref) => ScoreRepo(ref.watch(dbProvider)));

final settingsRepoProvider = Provider((ref) => SettingsRepo(ref.watch(dbProvider)));

/// 서버 호출 창구. 주소가 주입되지 않았으면 configured가 false라 관련 기능이 숨음.
final apiClientProvider = Provider((ref) => ApiClient());

/// 코인 잔액과 익명 기기 등록. 처음 읽히는 순간 기기 등록과 잔액 조회를 시작함.
final coinWalletProvider = ChangeNotifierProvider<CoinWallet>((ref) {
  final wallet = CoinWallet(ref.watch(apiClientProvider))..init();
  ref.onDispose(wallet.dispose);
  return wallet;
});

/// 악보 분석. 서버 호출과 DB 반영, 되돌리기를 함께 다룸.
final aiAnalysisProvider = Provider(
  (ref) => AiAnalysisService(
    ref.watch(apiClientProvider),
    ref.watch(scoreRepoProvider),
    ref.watch(settingsRepoProvider),
  ),
);

/// 메트로놈 언락 상태. 앱이 뜨자마자 스토어에 물어봄.
final purchasesProvider = ChangeNotifierProvider<Purchases>((ref) {
  final p = Purchases(ref.watch(settingsRepoProvider));
  // 코인 영수증은 서버가 확인해야 적립되므로 지갑으로 넘김.
  // 여기서 false가 나오면 스토어 구매를 완료 처리하지 않아 다음에 다시 시도됨
  p.onCoinPurchase = (productId, purchaseToken) => ref
      .read(coinWalletProvider)
      .redeem(
        platform: Platform.isIOS ? 'ios' : 'android',
        productId: productId,
        purchaseToken: purchaseToken,
      );
  p.init();
  ref.onDispose(p.dispose);
  return p;
});

/// 오디오 엔진. 앱 시작 시 main에서 init을 마친 인스턴스로 덮어씀.
final audioProvider = Provider<AudioService>(
  (ref) => throw UnimplementedError('main에서 overrideWithValue로 초기화된 AudioService를 넣어야 함'),
);
