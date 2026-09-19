// 코인 지갑의 신원 교체 검증. 신원 파일이 곧 코인 소유권이라 늦게 끝난 등록이 새 신원을 덮거나
// 경고 없이 잔액을 버리면 산 코인에 다시 닿을 길이 사라짐.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baton/cloud/api_client.dart';
import 'package:baton/cloud/coin_wallet.dart';
import 'package:baton/cloud/device_credentials.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 경로별 응답을 정하는 서버 대역. 정하지 않은 경로는 404.
ApiClient fakeServer(Map<String, FutureOr<Map<String, dynamic>> Function(http.Request)> routes) =>
    ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        final route = routes[req.url.path];
        if (route == null) return http.Response.bytes(utf8.encode('{"error":"없음"}'), 404);
        return http.Response.bytes(utf8.encode(jsonEncode(await route(req))), 200);
      }),
    );

/// 이 신원을 돌려주는 등록·복구 응답 본문.
Map<String, dynamic> identity(String userId, {int balance = 0}) => {
  'userId': userId,
  'token': 'tok-$userId',
  'balance': balance,
  'recoveryCode': 'ABCD-EFGH-JKLM',
};

const _pricing = {'coinsPerPage': 1, 'packs': [], 'maxPagesPerCall': 8};

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('baton-wallet-test');
    AppPaths.overrideDocuments(docs);
  });

  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  test('등록이 늦게 끝나도 그 뒤에 한 가져오기가 남음', () async {
    final registering = Completer<Map<String, dynamic>>();
    final wallet = CoinWallet(
      fakeServer({
        '/v1/device/register': (_) => registering.future,
        '/v1/device/restore': (_) => identity('restored', balance: 30),
        '/v1/balance': (_) => {'balance': 0},
        '/v1/pricing': (_) => _pricing,
      }),
    );

    final init = wallet.init();
    final restore = wallet.restore('ABCD-EFGH-JKLM');
    await Future<void>.delayed(Duration.zero);
    registering.complete(identity('fresh'));
    await init;

    expect(await restore, RestoreResult.restored);
    expect(wallet.token, 'tok-restored');
    expect(wallet.balance, 30);
    expect((await loadDeviceCredentials())!.userId, 'restored');
  });

  test('토큰이 없을 때 온 영수증은 먼저 등록한 뒤 적립함', () async {
    final wallet = CoinWallet(
      fakeServer({
        '/v1/device/register': (_) => identity('fresh'),
        '/v1/purchase': (req) {
          expect(req.headers['authorization'], 'Bearer tok-fresh');
          return {'balance': 60, 'granted': 60, 'duplicate': false};
        },
      }),
    );

    final ok = await wallet.redeem(
      platform: 'ios',
      productId: 'baton_coins_60',
      purchaseToken: 'r',
    );
    expect(ok, isTrue);
    expect(wallet.balance, 60);
  });

  test('이 기기에 코인이 남아 있으면 확인 없이는 가져오지 않음', () async {
    var restoreCalls = 0;
    final wallet = CoinWallet(
      fakeServer({
        '/v1/device/register': (_) => identity('mine', balance: 60),
        '/v1/balance': (_) => {'balance': 60},
        '/v1/pricing': (_) => _pricing,
        '/v1/device/restore': (_) {
          restoreCalls++;
          return identity('other', balance: 5);
        },
      }),
    );
    await wallet.init();

    expect(await wallet.restore('ABCD-EFGH-JKLM'), RestoreResult.wouldDiscard);
    expect(restoreCalls, 0);
    expect(await wallet.restore('ABCD-EFGH-JKLM', discardCurrent: true), RestoreResult.restored);
    expect(restoreCalls, 1);
    expect(wallet.balance, 5);
  });

  test('오프라인으로 켜 잔액이 0으로 남아 있어도 가져오기 전에 서버 잔액을 다시 보고 경고함', () async {
    await saveDeviceCredentials(const DeviceCredentials(token: 'tok-mine', userId: 'mine'));
    var online = false;
    var restoreCalls = 0;
    final wallet = CoinWallet(
      fakeServer({
        '/v1/balance': (_) {
          if (!online) throw http.ClientException('오프라인');
          return {'balance': 60};
        },
        '/v1/pricing': (_) => _pricing,
        '/v1/device/restore': (_) {
          restoreCalls++;
          return identity('other', balance: 5);
        },
      }),
    );
    await wallet.init();
    expect(wallet.ready, isTrue);
    expect(wallet.balance, 0);

    // 아직 오프라인이면 잔액을 모르므로 버려질 수 있다고 보고 멈춤
    expect(await wallet.restore('ABCD-EFGH-JKLM'), RestoreResult.wouldDiscard);
    expect(wallet.lastError, isNotNull);

    online = true;
    expect(await wallet.restore('ABCD-EFGH-JKLM'), RestoreResult.wouldDiscard);
    expect(wallet.balance, 60);
    expect(wallet.lastError, isNull);
    expect(restoreCalls, 0);
  });

  test('대시 없이 넣은 복구 코드는 발급 모양으로 맞춰 보내고, 모양이 틀리면 보내지 않음', () async {
    final sent = <String>[];
    final wallet = CoinWallet(
      fakeServer({
        '/v1/device/restore': (req) {
          sent.add((jsonDecode(req.body) as Map<String, dynamic>)['recoveryCode'] as String);
          return identity('other');
        },
      }),
    );

    expect(await wallet.restore('abcd efgh jklm'), RestoreResult.restored);
    expect(sent, ['ABCD-EFGH-JKLM']);
    expect(await wallet.restore('ABCD-EFGH'), RestoreResult.failed);
    expect(sent, hasLength(1));
    expect(wallet.lastError, isNotNull);
  });

  test('복구 코드 정규화는 대시·공백·대소문자를 무시하고 발급에 없는 문자는 거부함', () {
    expect(normalizeRecoveryCode('ABCDEFGHJKLM'), 'ABCD-EFGH-JKLM');
    expect(normalizeRecoveryCode(' abcd-efgh jklm '), 'ABCD-EFGH-JKLM');
    expect(normalizeRecoveryCode('ABCD-EFGH-JKL0'), isNull);
    expect(normalizeRecoveryCode('ABCD-EFGH-JKLMN'), isNull);
  });
}
