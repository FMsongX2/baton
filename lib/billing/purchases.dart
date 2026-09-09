// 메트로놈 언락 상태. 스토어 구매 스트림을 듣고 결과를 로컬에 캐시함.
// 서버 영수증 검증은 두지 않음. 1,200원짜리 언락 하나에 백엔드를 붙일 이유가 없고,
// 우회 가능성은 의도적으로 받아들인 트레이드오프.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/db/settings_repo.dart';

class Purchases extends ChangeNotifier {
  Purchases(this._settings);

  /// 스토어에 등록할 비소모성 상품 id.
  static const metronomeProductId = 'baton_metronome';

  /// 코인 묶음(소모성) 상품 id. 서버 receipts.ts의 COIN_PACKS와 같은 값이어야 함.
  /// 지급 코인 수는 서버가 정하고 앱은 id만 앎.
  static const coinProductIds = <String>{'baton_coins_10', 'baton_coins_60', 'baton_coins_150'};

  final SettingsRepo _settings;
  final _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  final _coinProducts = <String, ProductDetails>{};

  /// 코인 구매가 확인되면 서버에 영수증을 넘기는 다리. 서버 적립이 성공해야 true.
  /// true를 받기 전에는 스토어 구매를 완료 처리하지 않아 재전송으로 다시 시도할 수 있음.
  Future<bool> Function(String productId, String purchaseToken)? onCoinPurchase;
  bool _unlocked = false;
  bool _storeAvailable = false;
  bool _busy = false;
  String? _lastError;

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
  String? get lastError => _lastError;

  /// 캐시를 먼저 읽어 화면을 그린 뒤 스토어에 물어봄. 스토어가 없어도 앱은 굴러감.
  Future<void> init() async {
    _unlocked = await _settings.getBool(kMetronomeUnlockedKey);
    notifyListeners();

    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _lastError = '$e';
        _busy = false;
        notifyListeners();
      },
    );

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
      // 서버 적립에 실패해 완료 처리하지 않은 코인 구매가 남아 있을 수 있음.
      // iOS는 옵저버를 붙이면 미완료 거래를 스스로 다시 보내 주고, 여기서 복원을 부르면
      // Apple ID 로그인 창이 뜸. 스스로 보내 주지 않는 안드로이드에서만 조회함
      if (Platform.isAndroid) await _iap.restorePurchases();
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
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

  /// 코인 묶음을 삼. 소모성이라 buyConsumable로 사고, 적립은 서버가 영수증을 확인한 뒤에 함.
  Future<void> buyCoins(ProductDetails product) async {
    if (_busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      _lastError = '$e';
      _busy = false;
      notifyListeners();
    }
  }

  /// 기기를 바꾸거나 재설치한 경우 이미 산 것을 되살림.
  Future<void> restore() async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _lastError = '$e';
    }
    _busy = false;
    notifyListeners();
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
            // 서버가 코인을 넣지 못했으면 완료 처리하지 않고 넘어감.
            // 스토어가 다음에 같은 구매를 다시 보내 주므로 그때 재시도됨
            final granted = await onCoinPurchase?.call(
              p.productID,
              p.verificationData.serverVerificationData,
            );
            if (granted != true) continue;
          }
        case PurchaseStatus.error:
          _lastError = p.error?.message ?? '구매 실패';
        case PurchaseStatus.canceled:
          _lastError = null;
        case PurchaseStatus.pending:
          continue;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    _busy = false;
    notifyListeners();
  }

  /// 언락 상태를 켜고 저장함.
  Future<void> _unlock() async {
    _unlocked = true;
    await _settings.setBool(kMetronomeUnlockedKey, true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
