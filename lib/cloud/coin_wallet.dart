// 코인 잔액과 익명 기기 등록. 진실은 서버에 있고 여기서는 마지막으로 받은 값을 들고 있음.
// 토큰은 백업에 실리지 않는 별도 파일에 둠. 잃어버리면 복구 코드로만 되찾을 수 있음.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'device_credentials.dart';

/// 복구 코드로 가져오기를 한 결과.
enum RestoreResult {
  /// 가져와서 이 기기의 신원이 바뀜.
  restored,

  /// 이 기기에 남은 코인이 있거나 잔액을 확인하지 못해 버리기 전에 멈춤.
  /// 확인했으면 balance가 방금 받은 잔액, 못 했으면 마지막 값이고 사유는 lastError.
  /// 사용자가 확인하면 discardCurrent로 다시 부름.
  wouldDiscard,

  /// 코드가 틀렸거나 서버에 닿지 못함. 사유는 lastError.
  failed,
}

/// 복구 코드에 쓰는 문자. 서버 auth.ts의 RECOVERY_ALPHABET과 같음. 0/O, 1/I 같은 혼동 쌍을 뺌.
const _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 입력한 복구 코드를 발급 모양(XXXX-XXXX-XXXX)으로 맞춤. 대시·공백·대소문자는 무시함.
/// 발급 문자 12자가 아니면 null이라 서버에 보내기 전에 막을 수 있음.
String? normalizeRecoveryCode(String input) {
  final chars = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (chars.length != 12 || chars.split('').any((c) => !_recoveryAlphabet.contains(c))) {
    return null;
  }
  return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
}

class CoinWallet extends ChangeNotifier {
  CoinWallet(this._api);

  final ApiClient _api;

  String? _token;
  int _balance = 0;
  Pricing? _pricing;
  String? _lastError;

  /// 신원을 읽거나 바꾸는 작업의 줄. 앞 작업이 끝나야 다음이 시작되므로
  /// 늦게 끝난 등록이 방금 가져온 신원이나 적립된 신원을 덮지 못함.
  Future<void> _queue = Future.value();

  /// 줄에 서 있거나 도는 작업 수.
  int _pending = 0;

  /// 서버 주소가 빌드에 주입됐는지. 아니면 AI 기능을 통째로 감춤.
  bool get available => _api.configured;

  bool get ready => _token != null;

  /// 서버 호출에 쓰는 토큰. 등록 전이면 null.
  String? get token => _token;
  int get balance => _balance;
  Pricing? get pricing => _pricing;

  /// 신원 작업(등록·조회·적립·가져오기·복구 코드)이 줄에 있는지. 있으면 새 작업 버튼을 막음.
  bool get busy => _pending > 0;
  String? get lastError => _lastError;

  /// 작업을 줄 끝에 세우고 차례가 오면 실행함. 앞 작업의 실패는 뒤 작업을 막지 않음.
  Future<T> _serial<T>(Future<T> Function() op) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    _pending++;
    notifyListeners();
    try {
      await previous;
      return await op();
    } finally {
      _pending--;
      done.complete();
      notifyListeners();
    }
  }

  /// 저장된 토큰을 읽고, 없으면 이 기기를 새로 등록함. 실패해도 앱은 그대로 굴러감.
  /// 다른 기기가 복구 코드로 코인을 가져가면 이 토큰이 무효가 되므로 그때는 새로 등록함.
  Future<void> init() async {
    if (!available) return;
    await _serial(() async {
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
    });
  }

  /// 새 기기로 등록함. 등록 때 받는 복구 코드는 보여 주지 않으므로 옮기기 전에 새로 받아야 함.
  Future<void> _register() async {
    final id = await _api.registerDevice();
    await _persist(id);
    _lastError = null;
  }

  /// 무효가 된 토큰을 지움. 남겨 두면 다음 실행에서도 같은 401을 반복함.
  Future<void> _forgetToken() async {
    _token = null;
    _balance = 0;
    await clearDeviceCredentials();
  }

  /// 발급받은 신원을 저장하고 화면 상태를 맞춤. 줄 안에서만 부름.
  Future<void> _persist(DeviceIdentity id) async {
    _token = id.token;
    _balance = id.balance;
    await saveDeviceCredentials(DeviceCredentials(token: id.token, userId: id.userId));
  }

  /// 복구 코드를 새로 받음. 받은 코드는 대기 상태라 [confirmRecoveryCode] 전까지 이전 코드가 통함.
  /// 실패하면 null이고 사유는 lastError.
  Future<String?> issueRecoveryCode() => _serial(() async {
    final token = _token;
    if (token == null) {
      _lastError = '아직 서버에 등록되지 않음';
      return null;
    }
    try {
      final code = await _api.issueRecoveryCode(token);
      _lastError = null;
      return code;
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  });

  /// 사용자가 받아 적은 코드를 적용함. 이 순간부터 이전 코드는 쓸 수 없음.
  /// 같은 코드로 다시 불러도 안전하므로 실패하면 그대로 다시 부르면 됨.
  Future<bool> confirmRecoveryCode(String code) => _serial(() async {
    final token = _token;
    if (token == null) return false;
    try {
      await _api.confirmRecoveryCode(token, code);
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  });

  /// 잔액을 다시 읽음. 첫 실행이 오프라인이어서 등록을 못 했으면 이때 다시 시도함.
  /// 그러지 않으면 앱을 껐다 켤 때까지 AI 기능이 계속 막힘.
  Future<void> refresh() async {
    if (!available) return;
    await _serial(() async {
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
    });
  }

  /// 복구 코드로 다른 기기의 코인을 이 기기로 옮김. 옮기면 이전 기기의 토큰은 무효가 됨.
  /// 이 기기의 신원은 버려지므로 남은 코인이 있거나 확인하지 못하면 discardCurrent 없이는 옮기지 않음.
  Future<RestoreResult> restore(String recoveryCode, {bool discardCurrent = false}) =>
      _serial(() async {
        final code = normalizeRecoveryCode(recoveryCode);
        if (code == null) {
          _lastError = '복구 코드는 XXXX-XXXX-XXXX 모양의 12자임';
          return RestoreResult.failed;
        }
        _lastError = null;
        if (!discardCurrent && await _mayDiscard()) return RestoreResult.wouldDiscard;
        try {
          await _persist(await _api.restoreDevice(code));
          return RestoreResult.restored;
        } catch (e) {
          _lastError = '$e';
          return RestoreResult.failed;
        }
      });

  /// 가져오면 이 기기의 코인이 버려지는지 서버 잔액을 다시 읽어 판단하고 balance를 갱신함.
  /// 오프라인으로 켜 잔액을 못 읽었으면 마지막 값이 0이라 믿을 수 없음. 읽지 못하면 버려진다고 봄.
  Future<bool> _mayDiscard() async {
    final token = _token;
    if (token == null) return false;
    try {
      _balance = await _api.balance(token);
      return _balance > 0;
    } on ApiUnauthorized {
      // 이 신원의 코인은 이미 다른 기기로 옮겨져 버릴 것이 없음
      return false;
    } catch (e) {
      _lastError = '이 기기의 잔액을 확인하지 못함: $e';
      return true;
    }
  }

  /// 스토어 영수증을 서버에 넘겨 코인을 받음. 성공해야 스토어 구매를 완료 처리할 수 있음.
  /// 아직 등록 전이면 먼저 등록함. 진행 중인 init은 줄에서 기다리므로 저장된 토큰을 놓치지 않음.
  Future<bool> redeem({
    required String platform,
    required String productId,
    required String purchaseToken,
  }) => _serial(() async {
    try {
      if (_token == null) await _register();
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
      return true;
    } catch (e) {
      _lastError = '산 코인을 아직 넣지 못함: $e';
      return false;
    }
  });

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

  /// 잔액을 서버 응답으로 갱신함. 분석 직후처럼 이미 아는 값이 있을 때 씀.
  void setBalance(int value) {
    _balance = value;
    notifyListeners();
  }
}
