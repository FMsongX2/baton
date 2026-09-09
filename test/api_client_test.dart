// 서버 응답 해석 검증. 코인이 모자란 응답을 오류로만 흘리면 사용자에게 얼마가 필요한지 알릴 수 없음.

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
}
