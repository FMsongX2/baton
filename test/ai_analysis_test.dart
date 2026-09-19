// AI 반영 검증. 잘못 읽은 마디수·템포가 남으면 연주 중 페이지가 밀리므로 되돌리기와
// 템포 환산, 못 읽은 쪽 알림, 끊긴 묶음의 id 유지(코인 이중 차감 방지)를 고정함.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:baton/cloud/api_client.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/score/ai_analysis.dart';
import 'package:baton/score/score_repo.dart';
import 'package:baton/score/timeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late BatonDatabase db;
  late ScoreRepo scores;
  late SettingsRepo settings;
  late AiAnalysisService ai;

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    scores = ScoreRepo(db);
    settings = SettingsRepo(db);
    ai = AiAnalysisService(ApiClient(), scores, settings);
  });

  tearDown(() => db.close());

  Future<int> makeScore() async {
    final id = await scores.createScore(name: '악보', pageCount: 3);
    await scores.updatePage(id, 0, barCount: 4);
    await scores.updatePage(id, 1, barCount: 5);
    await scores.updatePage(id, 2, barCount: 6);
    await scores.updateSettings(id, bpm: 90, timeSigNum: 3, timeSigDen: 4, clicksPerBar: 3);
    return id;
  }

  test('되돌리기 지점이 없으면 undo가 실패로 끝남', () async {
    final id = await makeScore();
    expect(await ai.hasUndo(id), isFalse);
    expect(await ai.undo(id), isFalse);
  });

  test('저장한 지점으로 마디수와 템포가 모두 돌아옴', () async {
    final id = await makeScore();
    await ai.saveUndoPoint(id);
    expect(await ai.hasUndo(id), isTrue);

    // AI가 덮어쓴 상황을 흉내 냄
    await scores.updatePage(id, 0, barCount: 99);
    await scores.updatePage(id, 1, barCount: 98);
    await scores.updateSettings(id, bpm: 200, timeSigNum: 7, timeSigDen: 8, clicksPerBar: 7);

    expect(await ai.undo(id), isTrue);
    final pages = await scores.pages(id);
    expect(pages.map((p) => p.barCount), [4, 5, 6]);
    final score = (await scores.score(id))!;
    expect(score.bpm, 90);
    expect(score.timeSigNum, 3);
    expect(score.clicksPerBar, 3);
  });

  test('한 번 되돌리면 지점이 사라져 두 번 되돌아가지 않음', () async {
    final id = await makeScore();
    await ai.saveUndoPoint(id);
    await scores.updatePage(id, 0, barCount: 99);
    expect(await ai.undo(id), isTrue);
    expect(await ai.hasUndo(id), isFalse);
    expect(await ai.undo(id), isFalse);
  });

  test('지점을 다시 저장하면 그 시점 기준으로 돌아감', () async {
    final id = await makeScore();
    await ai.saveUndoPoint(id);
    await scores.updatePage(id, 0, barCount: 50);
    await ai.saveUndoPoint(id);
    await scores.updatePage(id, 0, barCount: 99);

    await ai.undo(id);
    expect((await scores.pages(id)).first.barCount, 50);
  });

  test('깨진 지점은 조용히 실패하고 지금 설정을 건드리지 않음', () async {
    final id = await makeScore();
    await settings.set('ai_undo_$id', '망가진 json');
    expect(await ai.undo(id), isFalse);
    expect((await scores.pages(id)).map((p) => p.barCount), [4, 5, 6]);
  });

  test('표기 음표와 클릭 음표가 다르면 클릭 템포로 환산함', () {
    double? convert(double bpm, String unit, int n, int d) =>
        clickBpmFromMarking(bpm, unit, tsNum: n, tsDen: d, clicksPerBar: defaultClicksPerBar(n, d));
    expect(convert(120, 'quarter', 4, 4), 120);
    expect(convert(144, 'quarter', 2, 2), 72);
    expect(convert(168, 'eighth', 6, 8), 56);
    expect(convert(60, 'dotted_quarter', 3, 8), 180);
    expect(convert(60, 'dotted_quarter', 6, 8), 60);
    // 음표를 모르거나 다룰 수 없는 템포가 되면 반영하지 않음
    expect(clickBpmFromMarking(120, null, tsNum: 4, tsDen: 4, clicksPerBar: 4), isNull);
    expect(convert(200, 'dotted_quarter', 3, 8), isNull);
  });

  test('숫자 표기 템포만 박자표 기준으로 환산해 반영하고 용어로 고른 값은 버림', () async {
    final id = await makeScore();
    final wordOnly = await ai.applyAnalyses(
      id,
      pageCount: 3,
      responses: [
        analysis(pages: [1], bpm: 132, source: 'tempo_word'),
      ],
      attempted: [0],
    );
    expect(wordOnly.bpmApplied, isFalse);
    expect((await scores.score(id))!.bpm, 90);

    final marked = await ai.applyAnalyses(
      id,
      pageCount: 3,
      responses: [
        analysis(pages: [1], bpm: 132, source: 'tempo_word'),
        analysis(pages: [2], bpm: 144, unit: 'quarter', source: 'marking', ts: (2, 2)),
      ],
      attempted: [0, 1],
    );
    expect(marked.bpmApplied, isTrue);
    final score = (await scores.score(id))!;
    expect(score.bpm, 72);
    expect(score.clicksPerBar, 2);
  });

  test('박자표를 못 읽었으면 지금 설정의 클릭 단위로 환산함', () async {
    final id = await makeScore(); // 3/4, 마디당 3클릭
    await ai.applyAnalyses(
      id,
      pageCount: 3,
      responses: [
        analysis(pages: [1], bpm: 40, unit: 'dotted_half', source: 'marking'),
      ],
      attempted: [0],
    );
    expect((await scores.score(id))!.bpm, 120);
  });

  test('보냈지만 결과가 없는 쪽을 알림에 넘기고 그 쪽 마디수는 건드리지 않음', () async {
    final id = await makeScore();
    final result = await ai.applyAnalyses(
      id,
      pageCount: 3,
      responses: [
        analysis(pages: [1, 3]),
      ],
      attempted: [0, 1, 2],
    );
    expect(result.appliedPages, 2);
    expect(result.missingPages, [2]);
    expect((await scores.pages(id))[1].barCount, 5);
  });

  test('끝까지 받지 못한 묶음 id는 다시 눌러도 같고 쪽 나눔이 바뀌면 새로 만듦', () async {
    final id = await makeScore();
    final first = await ai.batchIdFor(id, pageCount: 3, perCall: 8);
    expect(await ai.batchIdFor(id, pageCount: 3, perCall: 8), first);
    expect(await ai.batchIdFor(id, pageCount: 4, perCall: 8), isNot(first));
  });

  test('앞 묶음만 받고 끊긴 분석을 이어받으면 받은 쪽은 코인이 드는 쪽에서 뺌', () async {
    final id = await scores.createScore(name: '긴 악보', pageCount: 16);
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      analyzeRetryDelays: const [],
      httpClient: MockClient((req) async {
        // 첫 묶음(1~8쪽)만 읽고 둘째 묶음은 환불과 함께 실패함
        final body = ++calls == 1
            ? analysisJson(pages: [for (var p = 1; p <= 8; p++) p])
            : {'error': '분석에 실패해 코인을 돌려줌'};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), calls == 1 ? 200 : 502);
      }),
    );
    final service = AiAnalysisService(
      api,
      scores,
      settings,
      render: (path, indices, width, {onProgress}) async => [
        for (final i in indices) (index: i, png: Uint8List(1)),
      ],
    );
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 8), (charged: 16, pending: 0));

    final result = await service.analyzeAndApply(
      't',
      scoreId: id,
      pdfPath: 'unused.pdf',
      pageCount: 16,
      maxPagesPerCall: 8,
    );
    expect(result.partialReason, isNotNull);
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 8), (charged: 8, pending: 0));
    // 나누는 단위가 바뀌면 다른 분석이라 이어받을 것이 없음
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 4), (charged: 16, pending: 0));
  });

  test('렌더에 실패한 쪽이 낀 묶음은 결과를 받아도 코인이 드는 쪽으로 셈', () async {
    final id = await scores.createScore(name: '긴 악보', pageCount: 16);
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      analyzeRetryDelays: const [],
      httpClient: MockClient((req) async {
        // 4쪽이 빠진 첫 묶음은 읽고 둘째 묶음은 환불과 함께 실패함
        final body = ++calls == 1
            ? analysisJson(pages: [1, 2, 3, 5, 6, 7, 8])
            : {'error': '분석에 실패해 코인을 돌려줌'};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), calls == 1 ? 200 : 502);
      }),
    );
    final service = AiAnalysisService(
      api,
      scores,
      settings,
      render: (path, indices, width, {onProgress}) async => [
        for (final i in indices)
          if (i != 3) (index: i, png: Uint8List(1)),
      ],
    );

    final result = await service.analyzeAndApply(
      't',
      scoreId: id,
      pdfPath: 'unused.pdf',
      pageCount: 16,
      maxPagesPerCall: 8,
    );
    expect(result.partialReason, isNotNull);
    // 다시 누를 때 4쪽이 렌더되면 첫 묶음도 새 요청이라 전 쪽이 듦
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 8), (charged: 16, pending: 0));
  });

  test('분석을 멈추면 받은 결과도 반영하지 않고 묶음 기록을 남김', () async {
    final id = await scores.createScore(name: '긴 악보', pageCount: 16);
    final before = [for (final p in await scores.pages(id)) p.barCount];
    final stop = Completer<void>();
    final ids = <String>[];
    final api = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((req) async {
        ids.add((jsonDecode(req.body) as Map<String, dynamic>)['requestId'] as String);
        if (ids.length == 1) {
          return http.Response.bytes(
            utf8.encode(jsonEncode(analysisJson(pages: [for (var p = 1; p <= 8; p++) p]))),
            200,
          );
        }
        // 둘째 묶음을 기다리는 동안 사용자가 멈춤
        stop.complete();
        return Completer<http.Response>().future;
      }),
    );
    final service = AiAnalysisService(
      api,
      scores,
      settings,
      render: (path, indices, width, {onProgress}) async => [
        for (final i in indices) (index: i, png: Uint8List(1)),
      ],
    );

    await expectLater(
      service.analyzeAndApply(
        't',
        scoreId: id,
        pdfPath: 'unused.pdf',
        pageCount: 16,
        maxPagesPerCall: 8,
        cancel: stop,
      ),
      throwsA(isA<AnalysisCancelled>()),
    );
    expect([for (final p in await scores.pages(id)) p.barCount], before);
    expect(await ai.hasUndo(id), isFalse);
    // 다시 누르면 같은 묶음 id로 보내 받은 첫 묶음은 코인 없이 돌아옴. 답을 기다리다 멈춘 둘째 묶음은
    // 서버가 이미 코인을 뺐을 수 있어 드는 쪽이 아니라 답을 못 받은 쪽으로 셈
    final batchId = await service.batchIdFor(id, pageCount: 16, perCall: 8);
    expect(ids.first, startsWith('$batchId-'));
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 8), (charged: 0, pending: 8));
  });

  test('묶음 기록을 쓰는 도중 멈추면 분석 요청을 시작하지 않음', () async {
    // 첫 쓰기는 묶음 id, 둘째는 보낸 쪽 기록. 시작한 요청은 멈춰도 서버에 닿아 코인이 빠짐
    for (final stopAt in [1, 2]) {
      final id = await scores.createScore(name: '악보', pageCount: 8);
      final stop = Completer<void>();
      var writes = 0;
      var calls = 0;
      final service = AiAnalysisService(
        ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((req) async {
            calls++;
            final body = analysisJson(pages: [for (var p = 1; p <= 8; p++) p]);
            return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
          }),
        ),
        scores,
        _WriteHookSettings(db, (key) {
          if (key == 'ai_batch_$id' && ++writes == stopAt) stop.complete();
        }),
        render: (path, indices, width, {onProgress}) async => [
          for (final i in indices) (index: i, png: Uint8List(1)),
        ],
      );

      await expectLater(
        service.analyzeAndApply(
          't',
          scoreId: id,
          pdfPath: 'unused.pdf',
          pageCount: 8,
          maxPagesPerCall: 8,
          cancel: stop,
        ),
        throwsA(isA<AnalysisCancelled>()),
      );
      // 시작했다 버린 요청이 있으면 그 전송이 끝날 때까지 흘려보냄
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0, reason: '$stopAt번째 쓰기 도중 멈춤');
      // 보낸 쪽으로 기록된 뒤 멈췄으면 다음에 같은 id로 이어받을 쪽으로 남음
      expect(
        await service.pagesToCharge(id, pageCount: 8, perCall: 8),
        stopAt == 1 ? (charged: 8, pending: 0) : (charged: 0, pending: 8),
      );
    }
  });

  test('마지막 응답 뒤 받은 쪽을 기록하는 도중 멈추면 반영하지 않고 묶음 기록을 남김', () async {
    // 쓰기 순서: 묶음 id, 보낸 쪽, 받은 쪽. 셋째 쓰기가 끝나면 남은 것은 반영뿐
    final id = await scores.createScore(name: '악보', pageCount: 8);
    final stop = Completer<void>();
    var writes = 0;
    final service = AiAnalysisService(
      ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((req) async {
          final body = analysisJson(pages: [for (var p = 1; p <= 8; p++) p]);
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      ),
      scores,
      _WriteHookSettings(db, (key) {
        if (key == 'ai_batch_$id' && ++writes == 3) stop.complete();
      }),
      render: (path, indices, width, {onProgress}) async => [
        for (final i in indices) (index: i, png: Uint8List(1)),
      ],
    );
    final before = (await scores.pages(id)).map((p) => p.barCount).toList();

    await expectLater(
      service.analyzeAndApply(
        't',
        scoreId: id,
        pdfPath: 'unused.pdf',
        pageCount: 8,
        maxPagesPerCall: 8,
        cancel: stop,
      ),
      throwsA(isA<AnalysisCancelled>()),
    );
    expect((await scores.pages(id)).map((p) => p.barCount), before, reason: '7마디로 반영되면 안 됨');
    // 모두 받은 쪽으로 남아 다시 누르면 같은 id로 코인 없이 받음
    expect(await service.pagesToCharge(id, pageCount: 8, perCall: 8), (charged: 0, pending: 0));
    expect(await settings.get('ai_batch_$id'), isNotNull);
  });

  test('재전송 끝에도 답을 못 받은 묶음은 답을 못 받은 쪽으로 남김', () async {
    final id = await scores.createScore(name: '긴 악보', pageCount: 16);
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      analyzeRetryDelays: const [],
      httpClient: MockClient((req) async {
        // 둘째 묶음은 서버가 아직 처리 중(409)이라 결과를 못 받고 끝남
        final body = ++calls == 1
            ? analysisJson(pages: [for (var p = 1; p <= 8; p++) p])
            : {'error': '같은 분석이 아직 진행 중', 'pending': true};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), calls == 1 ? 200 : 409);
      }),
    );
    final service = AiAnalysisService(
      api,
      scores,
      settings,
      render: (path, indices, width, {onProgress}) async => [
        for (final i in indices) (index: i, png: Uint8List(1)),
      ],
    );

    final result = await service.analyzeAndApply(
      't',
      scoreId: id,
      pdfPath: 'unused.pdf',
      pageCount: 16,
      maxPagesPerCall: 8,
    );
    expect(result.partialReason, isNotNull);
    expect(await service.pagesToCharge(id, pageCount: 16, perCall: 8), (charged: 0, pending: 8));
  });
}

/// 서버 분석 응답 본문. pages는 1부터 센 쪽 번호이며 모두 7마디로 읽힌 것으로 둠.
Map<String, dynamic> analysisJson({required List<int> pages}) => {
  'pages': [
    for (final p in pages) {'page': p, 'bars': 7, 'confidence': 'high'},
  ],
  'bpm': null,
  'bpmSource': 'none',
  'coinsSpent': pages.length,
  'balance': 0,
};

/// 서버 분석 응답 하나. pages는 1부터 센 쪽 번호이며 모두 7마디로 읽힌 것으로 둠.
ScoreAnalysis analysis({
  required List<int> pages,
  double? bpm,
  String? unit,
  String source = 'none',
  (int, int)? ts,
}) => ScoreAnalysis(
  pages: [for (final p in pages) PageAnalysis(page: p, bars: 7, confidence: 'high')],
  bpm: bpm,
  bpmUnit: unit,
  bpmSource: source,
  timeSigNum: ts?.$1,
  timeSigDen: ts?.$2,
  coinsSpent: pages.length,
  balance: 0,
);

/// 쓰기를 시작한 직후 훅을 부르는 설정 저장소. 쓰기를 기다리는 도중에 멈추는 경우를 만듦.
class _WriteHookSettings extends SettingsRepo {
  /// 쓰기마다 키를 넘겨 부를 훅을 받음.
  _WriteHookSettings(super.db, this.onWrite);

  final void Function(String key) onWrite;

  /// 쓰기를 시작하고 훅을 부른 뒤 쓰기가 끝나길 기다리게 둠.
  @override
  Future<void> set(String key, String value) {
    final write = super.set(key, value);
    onWrite(key);
    return write;
  }
}
