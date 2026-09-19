// 코인 구매 마무리 순서 검증. 서버 적립이 확인되기 전에 거래를 끝내거나 소비하면
// 적립이 실패했을 때 결제한 코인을 되찾을 길이 없음. 복원 결과도 사용자에게 알려야 함.

import 'dart:async';

import 'package:baton/billing/purchases.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

/// 스토어 대역. 구매 결과는 updates로 흘리고, 끝내기·구매 요청은 기록만 함.
class _FakeStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  final bought = <String>[];
  final autoConsumed = <bool>[];
  List<PurchaseDetails> restorable = [];

  /// iOS(SK2)처럼 복원 호출에 먼저 답하고 결과 묶음은 나중에 보냄.
  bool restoreLate = false;

  /// SK2 finish가 거래를 찾지 못했을 때처럼 끝내기에 끝내 답하지 않음.
  bool hangComplete = false;

  /// 흘린 구매 결과 묶음을 그대로 내보냄.
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  /// 늘 스토어가 있다고 답함.
  @override
  Future<bool> isAvailable() async => true;

  /// 상품은 없다고 답함. 구매 흐름만 봄.
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async =>
      ProductDetailsResponse(productDetails: [], notFoundIDs: identifiers.toList());

  /// 구매 요청과 자동 소비 여부를 기록함.
  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    bought.add(purchaseParam.productDetails.id);
    autoConsumed.add(autoConsume);
    return true;
  }

  /// 끝낸 거래를 기록함. hangComplete면 답하지 않음.
  @override
  Future<void> completePurchase(PurchaseDetails purchase) {
    if (hangComplete) return Completer<void>().future;
    completed.add(purchase);
    return Future.value();
  }

  /// 복원 결과 한 묶음을 흘림. 안드로이드는 흘린 뒤 답하고, restoreLate면 답한 뒤에 흘림.
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    if (!restoreLate) return updates.add(restorable);
    final batch = restorable;
    Timer(const Duration(milliseconds: 20), () => updates.add(batch));
  }
}

/// 안드로이드 추가 기능 대역. 소비만 기록함.
class _FakeAndroid implements InAppPurchaseAndroidPlatformAddition {
  final consumed = <PurchaseDetails>[];

  /// 소비에 돌려줄 응답. 이미 소비된 구매면 itemNotOwned.
  BillingResponse consumeResponse = BillingResponse.ok;

  /// 소비를 기록하고 consumeResponse로 답함.
  @override
  Future<BillingResultWrapper> consumePurchase(PurchaseDetails purchase) async {
    consumed.add(purchase);
    return BillingResultWrapper(responseCode: consumeResponse);
  }

  /// 쓰지 않는 기능은 부르면 실패함.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// iOS처럼 끝내기를 기다리는 코인 구매.
PurchaseDetails _iosCoins(String id) => PurchaseDetails(
  purchaseID: id,
  productID: 'baton_coins_10',
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'receipt-$id',
    source: 'app_store',
  ),
  transactionDate: '0',
  status: PurchaseStatus.purchased,
)..pendingCompletePurchase = true;

/// 메트로놈 구매 기록.
PurchaseDetails _metronome(PurchaseStatus status) => PurchaseDetails(
  productID: Purchases.metronomeProductId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'm',
    source: 'app_store',
  ),
  transactionDate: '0',
  status: status,
)..pendingCompletePurchase = status == PurchaseStatus.purchased;

/// 안드로이드 코인 구매. 주문 번호가 빈 경우(프로모션 코드 등)를 함께 흉내 냄.
GooglePlayPurchaseDetails _androidCoins(String token) => GooglePlayPurchaseDetails(
  productID: 'baton_coins_10',
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '0',
  status: PurchaseStatus.purchased,
  billingClientPurchase: PurchaseWrapper(
    orderId: '',
    packageName: 'baton',
    purchaseTime: 0,
    purchaseToken: token,
    signature: '',
    products: const ['baton_coins_10'],
    isAutoRenewing: false,
    originalJson: '{}',
    isAcknowledged: false,
    purchaseState: PurchaseStateWrapper.purchased,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BatonDatabase db;
  late _FakeStore store;
  late _FakeAndroid android;
  late Purchases purchases;
  late bool grant;
  late List<String> redeemed;

  setUpAll(() {
    // 첫 접근 때 테스트 기본 플랫폼(안드로이드)의 실제 플러그인이 붙지 않게 함
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() async {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    store = _FakeStore();
    android = _FakeAndroid();
    InAppPurchasePlatform.instance = store;
    InAppPurchasePlatformAddition.instance = android;
    grant = false;
    redeemed = [];
    purchases = Purchases(SettingsRepo(db), storeTimeout: const Duration(milliseconds: 200))
      ..onCoinPurchase = (productId, token) async {
        redeemed.add(token);
        return grant;
      };
    await purchases.init();
  });

  tearDown(() async {
    purchases.dispose();
    await db.close();
  });

  /// 스트림으로 흘린 묶음이 처리될 때까지 기다림.
  Future<void> deliver(List<PurchaseDetails> list) async {
    store.updates.add(list);
    await Future<void>.delayed(Duration.zero);
    // 처리 줄이 멈추면 여기서 실패하게 한도를 둠
    await purchases.settled.timeout(const Duration(seconds: 2));
  }

  test('서버 적립이 실패한 코인 구매는 끝내지 않고, 다시 적립되면 그때 끝냄', () async {
    await deliver([_iosCoins('a')]);
    expect(redeemed, ['receipt-a']);
    expect(store.completed, isEmpty);

    grant = true;
    await purchases.retryCoinPurchases();
    expect(redeemed, ['receipt-a', 'receipt-a']);
    expect(store.completed, hasLength(1));
  });

  test('안드로이드 코인 구매는 적립이 확인된 뒤에만 소비하고 확인 처리는 따로 하지 않음', () async {
    await deliver([_androidCoins('tok-1'), _androidCoins('tok-2')]);
    expect(android.consumed, isEmpty);

    grant = true;
    await purchases.retryCoinPurchases();
    expect(android.consumed.map((p) => p.verificationData.serverVerificationData), [
      'tok-1',
      'tok-2',
    ]);
    expect(store.completed, isEmpty);
  });

  test('적립 못 한 같은 묶음을 다시 사려 하면 새 결제 대신 앞 구매부터 다시 적립함', () async {
    await deliver([_iosCoins('a')]);
    final product = ProductDetails(
      id: 'baton_coins_10',
      title: '10코인',
      description: '',
      price: '₩1,200',
      rawPrice: 1200,
      currencyCode: 'KRW',
    );

    await purchases.buyCoins(product);
    expect(store.bought, isEmpty);
    expect(redeemed, hasLength(2));
    // 코인 쪽 오류는 메트로놈 오류 칸이 아니라 코인 칸에 남음
    expect(purchases.coinError, isNotNull);
    expect(purchases.lastError, isNull);

    grant = true;
    await purchases.buyCoins(product);
    expect(store.bought, isEmpty);
    expect(store.completed, hasLength(1));

    await purchases.buyCoins(product);
    expect(store.bought, ['baton_coins_10']);
    // 테스트 기본 플랫폼은 안드로이드라 자동 소비를 꺼야 함
    expect(store.autoConsumed, [false]);
  });

  test('안드로이드에서 이미 소비된 구매를 다시 정리하면 끝난 것으로 보고 같은 묶음을 다시 살 수 있음', () async {
    // 한도를 넘겨 실패로 남았지만 실제로는 된 소비나, 두 복원 묶음에 든 같은 구매의 두 번째 정리
    grant = true;
    android.consumeResponse = BillingResponse.itemNotOwned;
    await deliver([_androidCoins('tok-1')]);
    expect(purchases.coinError, isNull);

    await purchases.buyCoins(
      ProductDetails(
        id: 'baton_coins_10',
        title: '10코인',
        description: '',
        price: '₩1,200',
        rawPrice: 1200,
        currencyCode: 'KRW',
      ),
    );
    expect(store.bought, ['baton_coins_10']);
  });

  test('복원할 것이 없으면 없다고, 메트로놈이 돌아오면 해제됐다고 알림', () async {
    expect(await purchases.restore(), PurchaseRestore.nothing);

    store.restorable = [_metronome(PurchaseStatus.restored)];
    expect(await purchases.restore(), PurchaseRestore.unlocked);
    expect(purchases.unlocked, isTrue);
  });

  test('iOS처럼 복원 결과가 호출이 끝난 뒤에 와도 그 결과를 보고 알림', () async {
    store
      ..restoreLate = true
      ..restorable = [_metronome(PurchaseStatus.restored)];
    expect(await purchases.restore(), PurchaseRestore.unlocked);
  });

  test('스토어가 거래 정리에 답하지 않아도 뒤의 구매 처리와 복원이 멈추지 않음', () async {
    store.hangComplete = true;
    await deliver([_metronome(PurchaseStatus.purchased)]);
    expect(purchases.unlocked, isTrue);

    grant = true;
    await deliver([_iosCoins('a')]);
    expect(redeemed, ['receipt-a']);
    expect(purchases.coinError, isNull);
    expect(await purchases.restore().timeout(const Duration(seconds: 2)), PurchaseRestore.unlocked);
  });
}
