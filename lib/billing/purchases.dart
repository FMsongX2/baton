// 메트로놈 언락과 코인 묶음 구매. 스토어 구매 스트림을 듣고 언락은 로컬에 캐시함.
// 언락은 서버 영수증 검증을 두지 않음. 1,200원짜리 언락 하나에 백엔드를 붙일 이유가 없고,
// 우회 가능성은 의도적으로 받아들인 트레이드오프. 코인은 서버 적립을 확인한 뒤에만 거래를 끝냄.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show BillingResponse;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../core/db/settings_repo.dart';

/// 설정에서 구매 복원을 누른 결과.
enum PurchaseRestore {
  /// 메트로놈이 잠금 해제된 상태로 끝남.
  unlocked,

  /// 스토어가 이 계정의 메트로놈 구매를 돌려주지 않음.
  nothing,

  /// 스토어 호출이 실패함. 사유는 lastError.
  failed,
}

class Purchases extends ChangeNotifier {
  /// 구매 관리자를 만듦. 스토어 구독은 init에서 시작함.
  Purchases(this._settings, {this.storeTimeout = const Duration(seconds: 15)});

  /// 스토어가 답하지 않을 때 기다리는 한도. 거래 정리(finish·consume)와 복원 결과 묶음에 씀.
  /// SK2 finish는 거래를 찾지 못하면 끝내 답하지 않아, 한도가 없으면 처리 줄 전체가 멈춤.
  final Duration storeTimeout;

  /// 스토어에 등록할 비소모성 상품 id.
  static const metronomeProductId = 'baton_metronome';

  /// 코인 묶음(소모성) 상품 id. 서버 receipts.ts의 COIN_PACKS와 같은 값이어야 함.
  /// 지급 코인 수는 서버가 정하고 앱은 id만 앎.
  static const coinProductIds = <String>{'baton_coins_10', 'baton_coins_60', 'baton_coins_150'};

  final SettingsRepo _settings;
  final _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  AppLifecycleListener? _lifecycle;
  ProductDetails? _product;
  final _coinProducts = <String, ProductDetails>{};

  /// 적립이나 소비를 마치지 못해 끝내지 않은 코인 구매. 거래 id로 묶음.
  /// 앱을 다시 켜면 스토어가 다시 보내 주지만, 그 전에도 복귀·새로고침·재구매 때 다시 시도함.
  final _unsettled = <String, PurchaseDetails>{};

  /// 구매 결과 처리의 줄. 스트림 묶음과 재시도가 같은 구매를 동시에 적립하지 않게 차례로 돌림.
  Future<void> _processing = Future.value();

  /// restore가 기다리는 복원 결과 묶음. 그 묶음 처리가 끝나면 풀림.
  Completer<void>? _restoreBatch;

  /// 코인 구매가 확인되면 서버에 영수증을 넘기는 다리. 서버 적립이 성공해야 true.
  /// true를 받기 전에는 스토어 구매를 완료·소비하지 않아 재전송으로 다시 시도할 수 있음.
  Future<bool> Function(String productId, String purchaseToken)? onCoinPurchase;
  bool _unlocked = false;
  bool _storeAvailable = false;
  bool _busy = false;
  String? _lastError;
  String? _coinError;

  /// 메트로놈을 쓸 수 있는지. 스토어 확인 전에는 마지막으로 저장된 값을 씀.
  bool get unlocked => _unlocked;

  /// 스토어에서 받은 상품 정보. 가격 표기에 씀.
  ProductDetails? get product => _product;

  /// 코인 묶음 상품들. 스토어가 준 현지 가격 순으로 보여 줌.
  List<ProductDetails> get coinProducts {
    final list = _coinProducts.values.toList();
    list.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return list;
  }

  bool get storeAvailable => _storeAvailable;
  bool get busy => _busy;

  /// 메트로놈 구매·복원과 스토어 쪽 오류.
  String? get lastError => _lastError;

  /// 코인 구매·적립 정리 쪽 오류. 설정의 코인 구역에 따로 보임.
  String? get coinError => _coinError;

  /// 지금까지 줄에 들어온 구매 처리가 모두 끝나면 완료됨. 테스트가 결과를 기다릴 때 씀.
  @visibleForTesting
  Future<void> get settled => _processing;

  /// 캐시를 먼저 읽어 화면을 그린 뒤 스토어에 물어봄. 스토어가 없어도 앱은 굴러감.
  /// 앱이 다시 앞으로 오면 적립 못 한 코인 구매를 다시 시도함.
  Future<void> init() async {
    _unlocked = await _settings.getBool(kMetronomeUnlockedKey);
    notifyListeners();

    _sub = _iap.purchaseStream.listen(
      _onStream,
      onError: (Object e) {
        _lastError = '$e';
        _busy = false;
        notifyListeners();
      },
    );
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(retryCoinPurchases()));

    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) return;
      final resp = await _iap.queryProductDetails({metronomeProductId, ...coinProductIds});
      for (final p in resp.productDetails) {
        if (p.id == metronomeProductId) {
          _product = p;
        } else if (coinProductIds.contains(p.id)) {
          _coinProducts[p.id] = p;
        }
      }
      // 서버 적립에 실패해 소비하지 않은 코인 구매가 남아 있을 수 있음.
      // iOS는 옵저버를 붙이면 미완료 거래를 스스로 다시 보내 주고, 여기서 복원을 부르면
      // Apple ID 로그인 창이 뜸. 스스로 보내 주지 않는 안드로이드에서만 조회함
      if (defaultTargetPlatform == TargetPlatform.android) await _iap.restorePurchases();
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  /// 스트림 묶음을 처리 줄에 세움. 기다리던 복원 결과 묶음이면 처리 뒤 restore를 깨움.
  /// 두 스토어 모두 복원 결과는 전부 restored인 한 묶음(빈 목록 포함)으로 옴.
  void _onStream(List<PurchaseDetails> list) {
    final done = _enqueue(() => _onPurchases(list));
    final waiter = _restoreBatch;
    if (waiter == null || list.any((p) => p.status != PurchaseStatus.restored)) return;
    _restoreBatch = null;
    unawaited(done.then((_) => waiter.complete()));
  }

  /// 구매 결과 처리 작업을 줄 끝에 세움. 작업이 던지면 사유를 남기고 줄은 계속 돎.
  Future<void> _enqueue(Future<void> Function() job) {
    return _processing = _processing.then((_) => job()).catchError((Object e) {
      _lastError = '$e';
      _busy = false;
      notifyListeners();
    });
  }

  /// 구매를 시작함. 결과는 purchaseStream으로 돌아옴.
  Future<void> buy() async {
    final p = _product;
    if (p == null || _busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
    } catch (e) {
      _lastError = '$e';
      _busy = false;
      notifyListeners();
    }
  }

  /// 코인 묶음을 삼. 적립은 서버가 영수증을 확인한 뒤에 하고, 그 뒤에야 거래를 끝냄.
  /// 적립 못 한 같은 묶음이 남아 있으면 스토어가 새 구매를 막으므로 그것부터 다시 적립함.
  Future<void> buyCoins(ProductDetails product) async {
    if (_busy) return;
    _busy = true;
    _coinError = null;
    notifyListeners();
    if (_unsettled.values.any((p) => p.productID == product.id)) {
      await retryCoinPurchases();
      if (_unsettled.values.any((p) => p.productID == product.id)) {
        _coinError = '앞서 산 같은 묶음을 아직 코인으로 바꾸지 못함. 연결을 확인하고 다시 누름';
      }
      _busy = false;
      notifyListeners();
      return;
    }
    try {
      // 안드로이드는 자동 소비를 끔. 켜 두면 서버 적립 전에 소비돼 적립이 실패하면 다시 받을 길이 없음.
      // iOS 플러그인은 자동 소비만 받고, 거래는 completePurchase(finish)로 끝냄.
      // 플랫폼은 플러그인이 스토어를 고르는 기준(defaultTargetPlatform)으로 봄
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        autoConsume: defaultTargetPlatform != TargetPlatform.android,
      );
    } catch (e) {
      _coinError = '$e';
      _busy = false;
      notifyListeners();
    }
  }

  /// 기기를 바꾸거나 재설치한 경우 이미 산 것을 되살리고 결과를 돌려줌.
  /// 결과는 스트림 묶음으로 오므로 그 묶음 처리까지 기다린 뒤 판단함. 안드로이드는 묶음을 넣은 뒤
  /// 답하지만 iOS(SK2)는 묶음을 따로 보내고 곧바로 답해 묶음이 더 늦게 올 수 있음.
  Future<PurchaseRestore> restore() async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    final batch = _restoreBatch = Completer<void>();
    var failed = false;
    try {
      await _iap.restorePurchases();
      await batch.future.timeout(storeTimeout);
    } on TimeoutException {
      _lastError = '스토어가 복원 결과를 주지 않음. 잠시 뒤 다시 누름';
      failed = true;
    } catch (e) {
      _lastError = '$e';
      failed = true;
    }
    if (identical(_restoreBatch, batch)) _restoreBatch = null;
    _busy = false;
    notifyListeners();
    if (_unlocked) return PurchaseRestore.unlocked;
    return failed ? PurchaseRestore.failed : PurchaseRestore.nothing;
  }

  /// 끝내지 못한 코인 구매를 다시 적립함. 앱 복귀, 잔액 새로고침, 같은 묶음 재구매 때 부름.
  Future<void> retryCoinPurchases() {
    if (_unsettled.isEmpty) return Future.value();
    return _enqueue(() async {
      for (final p in [..._unsettled.values]) {
        await _settleCoins(p);
      }
      notifyListeners();
    });
  }

  /// 구매·복원 결과 처리. 완료 표시를 빠뜨리면 스토어가 같은 구매를 계속 다시 보냄.
  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == metronomeProductId) {
            await _unlock();
          } else if (coinProductIds.contains(p.productID)) {
            await _settleCoins(p);
            continue;
          }
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          // 취소는 오류를 지우고, 코인 쪽 오류는 코인 구역에 보임
          final message = p.status == PurchaseStatus.error ? p.error?.message ?? '구매 실패' : null;
          if (coinProductIds.contains(p.productID)) {
            _coinError = message;
          } else {
            _lastError = message;
          }
        case PurchaseStatus.pending:
          continue;
      }
      // 끝나지 않은 거래는 스토어가 다시 보내므로 답이 없으면 기다리지 않고 넘어감
      if (p.pendingCompletePurchase) await _complete(p);
    }
    _busy = false;
    notifyListeners();
  }

  /// 코인 구매를 서버에 적립하고, 적립이 확인된 뒤에만 스토어 거래를 끝냄.
  /// 안드로이드는 소비(consume)가 확인을 겸하고 같은 묶음을 다시 살 수 있게 함. iOS는 finish로 끝냄.
  /// 적립이나 소비가 실패하면 끝내지 않고 들고 있어, 스토어 재전송이나 retryCoinPurchases로 다시 시도됨.
  /// 같은 영수증을 다시 적립해도 서버가 한 번만 넣으므로 재시도는 안전함.
  Future<void> _settleCoins(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    // 안드로이드 주문 번호는 프로모션 코드 구매 등에서 비어 오므로 구매 토큰으로 묶음
    final key = p is GooglePlayPurchaseDetails ? token : (p.purchaseID ?? token);
    _unsettled[key] = p;
    final granted = await onCoinPurchase?.call(p.productID, token);
    if (granted != true) return;
    if (!await _finishCoins(p)) {
      // 소비하지 못하면 같은 묶음을 다시 살 수 없으므로 들고 있다가 다시 시도함
      _coinError = '코인은 넣었지만 스토어 정리에 실패함. 잠시 뒤 자동으로 다시 시도함';
      return;
    }
    _unsettled.remove(key);
    if (_unsettled.isEmpty) _coinError = null;
  }

  /// 적립된 코인 구매의 스토어 거래를 끝냄. 이미 소비된 구매도 true, 실패하거나 한도 안에 답이 없으면 false.
  Future<bool> _finishCoins(PurchaseDetails p) async {
    try {
      if (p is GooglePlayPurchaseDetails) {
        final result = await _iap
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
            .consumePurchase(p)
            .timeout(storeTimeout);
        // 한도를 넘겼지만 실제로는 된 소비를 다시 하거나, 두 복원 묶음에 든 같은 구매를 두 번째로
        // 정리하면 itemNotOwned가 옴. 실패로 두면 세션 내내 같은 묶음을 살 수 없음
        return result.responseCode == BillingResponse.ok ||
            result.responseCode == BillingResponse.itemNotOwned;
      }
      // SK2 finish가 답하지 않는 건 거래를 찾지 못한 경우(이미 끝남)뿐이라 끝난 것으로 봄
      if (p.pendingCompletePurchase) await _complete(p);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 스토어 거래를 끝냄. 한도 안에 답이 없으면 기다리지 않고 돌아와 처리 줄이 멈추지 않게 함.
  Future<void> _complete(PurchaseDetails p) =>
      _iap.completePurchase(p).timeout(storeTimeout, onTimeout: () {});

  /// 언락 상태를 켜고 저장함.
  Future<void> _unlock() async {
    _unlocked = true;
    await _settings.setBool(kMetronomeUnlockedKey, true);
  }

  /// 스트림 구독과 앱 수명 리스너를 거둠.
  @override
  void dispose() {
    _sub?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
