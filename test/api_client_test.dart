// 서버 응답 해석과 분석 재전송 검증. 코인이 모자란 응답을 오류로만 흘리면 얼마가 필요한지 알릴 수 없고,
// 결과를 못 받은 분석을 새 id로 다시 보내면 코인이 또 빠지므로 같은 id로 다시 보내야 함.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:baton/cloud/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// http.Response는 문자열을 latin1으로 담아 한글이 깨지므로 바이트로 넘김.
ApiClient clientReturning(int status, Map<String, dynamic> body) => ApiClient(
  baseUrl: 'https://example.test',
  httpClient: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(body)), status)),
);

void main() {
  test('서버 주소가 없으면 기능이 꺼진 것으로 봄', () {
    expect(ApiClient(baseUrl: '').configured, isFalse);
    expect(ApiClient(baseUrl: 'https://example.test').configured, isTrue);
  });

  test('기기 등록 응답에서 복구 코드까지 읽음', () async {
    final api = clientReturning(200, {
      'userId': 'u1',
      'token': 't1',
      'balance': 0,
      'recoveryCode': 'ABCD-EFGH-JKLM',
    });
    final id = await api.registerDevice();
    expect(id.userId, 'u1');
    expect(id.token, 't1');
    expect(id.recoveryCode, 'ABCD-EFGH-JKLM');
  });

  test('코인이 모자라면 필요한 양과 잔액을 실어 던짐', () async {
    final api = clientReturning(402, {'error': '코인이 모자람', 'needed': 12, 'balance': 3});
    try {
      await api.analyze('t', requestId: 'req-1', pages: [(index: 0, png: Uint8List(0))]);
      fail('던져야 함');
    } on ApiException catch (e) {
      expect(e.isInsufficientCoins, isTrue);
      expect(e.needed, 12);
      expect(e.balance, 3);
      expect(e.message, '코인이 모자람');
    }
  });

  test('분석 결과에서 쪽별 마디수와 확신도를 읽음', () async {
    final api = clientReturning(200, {
      'pages': [
        {'page': 1, 'bars': 8, 'confidence': 'high'},
        {'page': 2, 'bars': 6, 'confidence': 'low'},
      ],
      'bpm': 132,
      'bpmSource': 'marking',
      'timeSigNum': 3,
      'timeSigDen': 4,
      'coinsSpent': 2,
      'balance': 18,
    });
    final res = await api.analyze('t', requestId: 'req-1', pages: [(index: 0, png: Uint8List(0))]);
    expect(res.pages.map((p) => p.bars), [8, 6]);
    expect(res.bpm, 132);
    expect(res.bpmSource, 'marking');
    expect(res.lowConfidenceCount, 1);
    expect(res.coinsSpent, 2);
    expect(res.balance, 18);
  });

  test('템포 표기가 없으면 bpm이 비어서 옴', () async {
    final api = clientReturning(200, {
      'pages': [
        {'page': 1, 'bars': 4, 'confidence': 'medium'},
      ],
      'bpm': null,
      'bpmSource': 'none',
      'timeSigNum': null,
      'timeSigDen': null,
      'coinsSpent': 1,
      'balance': 9,
    });
    final res = await api.analyze('t', requestId: 'req-1', pages: [(index: 0, png: Uint8List(0))]);
    expect(res.bpm, isNull);
    expect(res.bpmSource, 'none');
  });

  test('JSON이 아닌 응답도 사용자에게 보일 오류로 바뀜', () async {
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient(
        (_) async => http.Response.bytes(utf8.encode('<html>502</html>'), 502),
      ),
    );
    expect(() => api.balance('t'), throwsA(isA<ApiException>()));
  });

  test('전송이 끊기면 같은 requestId로 다시 보내 결과를 받음', () async {
    final s = analyzeServer([http.ClientException('끊김'), (200, _analysisOk)]);
    final res = await s.api.analyze(
      't',
      requestId: 'req-9',
      pages: [(index: 0, png: Uint8List(0))],
    );
    expect(s.ids, ['req-9', 'req-9']);
    expect(res.bpmUnit, 'quarter');
  });

  test('서버가 같은 분석을 처리 중이면 기다렸다가 같은 id로 다시 물음', () async {
    final s = analyzeServer([
      (409, {'error': '같은 분석이 아직 진행 중', 'pending': true}),
      (200, _analysisOk),
    ]);
    await s.api.analyze('t', requestId: 'req-9', pages: [(index: 0, png: Uint8List(0))]);
    expect(s.ids, ['req-9', 'req-9']);
  });

  test('코인이 모자라거나 환불을 마친 실패는 다시 보내지 않음', () async {
    for (final status in [402, 502]) {
      final s = analyzeServer([
        (status, {'error': '거절', 'needed': 3, 'balance': 0}),
      ]);
      await expectLater(
        s.api.analyze('t', requestId: 'req-9', pages: [(index: 0, png: Uint8List(0))]),
        throwsA(isA<ApiException>()),
      );
      expect(s.ids, hasLength(1));
    }
  });

  test('재시도 한도를 넘으면 마지막 오류를 던짐', () async {
    final s = analyzeServer([for (var i = 0; i < 4; i++) http.ClientException('끊김')]);
    await expectLater(
      s.api.analyze('t', requestId: 'req-9', pages: [(index: 0, png: Uint8List(0))]),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', isNull)),
    );
    expect(s.ids, hasLength(4));
  });

  test('분석을 멈추면 응답을 기다리지 않고 멈춤을 던짐', () async {
    final stop = Completer<void>();
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((_) {
        calls++;
        return Completer<http.Response>().future; // 응답이 오지 않는 회선
      }),
    );
    final running = api.analyze(
      't',
      requestId: 'req-9',
      pages: [(index: 0, png: Uint8List(0))],
      cancel: stop,
    );
    await Future<void>.delayed(Duration.zero);
    stop.complete();
    await expectLater(
      running.timeout(const Duration(seconds: 1)),
      throwsA(isA<AnalysisCancelled>()),
    );
    expect(calls, 1);
  });

  test('재전송을 기다리는 중에 멈추면 다시 보내지 않음', () async {
    final stop = Completer<void>();
    final ids = <String>[];
    final api = ApiClient(
      baseUrl: 'https://example.test',
      analyzeRetryDelays: const [Duration(seconds: 30)],
      httpClient: MockClient((req) async {
        ids.add((jsonDecode(req.body) as Map<String, dynamic>)['requestId'] as String);
        throw http.ClientException('끊김');
      }),
    );
    final running = api.analyze(
      't',
      requestId: 'req-9',
      pages: [(index: 0, png: Uint8List(0))],
      cancel: stop,
    );
    while (ids.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    stop.complete();
    await expectLater(
      running.timeout(const Duration(seconds: 1)),
      throwsA(isA<AnalysisCancelled>()),
    );
    expect(ids, ['req-9']);
  });

  test('복구 코드 확인은 받은 코드를 그대로 실어 보냄', () async {
    late Map<String, dynamic> sent;
    late String path;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        path = req.url.path;
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(utf8.encode(jsonEncode({'confirmed': true})), 200);
      }),
    );
    await api.confirmRecoveryCode('t', 'ABCD-EFGH-JKLM');
    expect(path, '/v1/device/recovery/confirm');
    expect(sent['recoveryCode'], 'ABCD-EFGH-JKLM');
  });
}

/// 분석 요청마다 실어 온 requestId를 모으고 응답을 차례대로 꺼내는 대역. 예외면 전송 실패로 던짐.
({ApiClient api, List<String> ids}) analyzeServer(List<Object> replies) {
  final ids = <String>[];
  var i = 0;
  final api = ApiClient(
    baseUrl: 'https://example.test',
    analyzeRetryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    httpClient: MockClient((req) async {
      ids.add((jsonDecode(req.body) as Map<String, dynamic>)['requestId'] as String);
      final reply = replies[i++];
      if (reply is Exception) throw reply;
      final (status, body) = reply as (int, Map<String, dynamic>);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    }),
  );
  return (api: api, ids: ids);
}

const _analysisOk = <String, dynamic>{
  'pages': [
    {'page': 1, 'bars': 8, 'confidence': 'high'},
  ],
  'bpm': 144,
  'bpmUnit': 'quarter',
  'bpmSource': 'marking',
  'timeSigNum': 2,
  'timeSigDen': 2,
  'coinsSpent': 1,
  'balance': 7,
};
