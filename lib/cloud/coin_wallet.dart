// 코인 잔액과 익명 기기 등록. 진실은 서버에 있고 여기서는 마지막으로 받은 값을 들고 있음.
// 토큰은 백업에 실리지 않는 별도 파일에 둠. 잃어버리면 복구 코드로만 되찾을 수 있음.

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'device_credentials.dart';

class CoinWallet extends ChangeNotifier {
  CoinWallet(this._api);

  final ApiClient _api;

  String? _token;
  int _balance = 0;
  Pricing? _pricing;
  String? _recoveryCode;
  String? _lastError;
  bool _busy = false;

  /// 서버 주소가 빌드에 주입됐는지. 아니면 AI 기능을 통째로 감춤.
  bool get available => _api.configured;

  bool get ready => _token != null;

  /// 서버 호출에 쓰는 토큰. 등록 전이면 null.
  String? get token => _token;
  int get balance => _balance;
  Pricing? get pricing => _pricing;
  bool get busy => _busy;
  String? get lastError => _lastError;

  /// 새로 발급받은 복구 코드. 서버는 해시만 들고 있어 이때 한 번만 평문으로 볼 수 있음.
  /// 사용자가 받아 적고 나면 지움.
  String? get recoveryCode => _recoveryCode;

  /// 저장된 토큰을 읽고, 없으면 이 기기를 새로 등록함. 실패해도 앱은 그대로 굴러감.
  /// 다른 기기가 복구 코드로 코인을 가져가면 이 토큰이 무효가 되므로 그때는 새로 등록함.
  Future<void> init() async {
    if (!available) return;
    _token = (await loadDeviceCredentials())?.token;
    try {
      if (_token == null) {
        await _register();
      } else {
        try {
          _balance = await _api.balance(_token!);
        } on ApiUnauthorized {
          // 토큰이 더 이상 통하지 않음. 들고 있어 봐야 모든 호출이 막히므로 버리고 다시 등록함
          await _forgetToken();
          await _register();
          _lastError = '이 기기의 코인이 다른 기기로 옮겨져 새 기기로 등록함';
        }
      }
      _pricing = await _api.pricing();
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  /// 새 기기로 등록하고 복구 코드를 화면에 보여 줄 수 있게 남김.
  Future<void> _register() async {
    final id = await _api.registerDevice();
    await _persist(id);
    _recoveryCode = id.recoveryCode;
    _lastError = null;
  }

  /// 무효가 된 토큰을 지움. 남겨 두면 다음 실행에서도 같은 401을 반복함.
  Future<void> _forgetToken() async {
    _token = null;
    _balance = 0;
    await clearDeviceCredentials();
  }

  /// 발급받은 신원을 저장하고 화면 상태를 맞춤.
  Future<void> _persist(DeviceIdentity id) async {
    _token = id.token;
    _balance = id.balance;
    await saveDeviceCredentials(DeviceCredentials(token: id.token, userId: id.userId));
  }

  /// 복구 코드를 새로 받음. 받는 순간 이전 코드는 쓸 수 없게 됨.
  /// 등록 직후 코드를 못 본 사용자가 기기를 바꿀 때 코인을 잃지 않게 하는 유일한 길.
  Future<bool> issueRecoveryCode() async {
    final token = _token;
    if (token == null) return false;
    _busy = true;
    notifyListeners();
    try {
      _recoveryCode = await _api.issueRecoveryCode(token);
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 잔액을 다시 읽음. 첫 실행이 오프라인이어서 등록을 못 했으면 이때 다시 시도함.
  /// 그러지 않으면 앱을 껐다 켤 때까지 AI 기능이 계속 막힘.
  Future<void> refresh() async {
    if (!available) return;
    final token = _token;
    try {
      if (token == null) {
        await _register();
      } else {
        try {
          _balance = await _api.balance(token);
        } on ApiUnauthorized {
          await _forgetToken();
          await _register();
        }
      }
      // 첫 실행이 오프라인이었으면 가격도 못 받았음. 그대로 두면 잘못된 비용을 보여 줌
      _pricing ??= await _api.pricing();
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  /// 복구 코드로 다른 기기의 코인을 이 기기로 옮김. 옮기면 이전 기기의 토큰은 무효가 됨.
  Future<bool> restore(String recoveryCode) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final id = await _api.restoreDevice(recoveryCode);
      await _persist(id);
      // 이 기기가 들고 있던 코드는 이제 버려진 사용자를 가리킴
      _recoveryCode = null;
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 스토어 영수증을 서버에 넘겨 코인을 받음. 성공해야 스토어 구매를 완료 처리할 수 있음.
  Future<bool> redeem({
    required String platform,
    required String productId,
    required String purchaseToken,
  }) async {
    if (_token == null) return false;
    try {
      try {
        _balance = await _redeemWith(_token!, platform, productId, purchaseToken);
      } on ApiUnauthorized {
        // 다른 기기가 코인을 가져가 이 토큰이 죽음. 새로 등록해 이 기기에 적립함.
        // 그러지 않으면 스토어가 같은 구매를 계속 되보내며 매번 같은 401에 걸림
        await _forgetToken();
        await _register();
        _balance = await _redeemWith(_token!, platform, productId, purchaseToken);
      }
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<int> _redeemWith(String token, String platform, String productId, String purchaseToken) =>
      _api.redeemPurchase(
        token,
        platform: platform,
        productId: productId,
        purchaseToken: purchaseToken,
      );

  /// 분석에 필요한 코인이 잔액 안에 드는지.
  bool canAfford(int pageCount) {
    final per = _pricing?.coinsPerPage ?? 1;
    return _balance >= pageCount * per;
  }

  /// 쪽수만큼 드는 코인.
  int costFor(int pageCount) => pageCount * (_pricing?.coinsPerPage ?? 1);

  /// 복구 코드를 화면에서 지움. 사용자가 확인했다고 누른 뒤 부름.
  void dismissRecoveryCode() {
    _recoveryCode = null;
    notifyListeners();
  }

  /// 잔액을 서버 응답으로 갱신함. 분석 직후처럼 이미 아는 값이 있을 때 씀.
  void setBalance(int value) {
    _balance = value;
    notifyListeners();
  }
}
