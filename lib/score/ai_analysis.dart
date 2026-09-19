// 악보를 서버에 보내 쪽별 마디수와 템포를 받아 설정에 반영함.
// 추정이 틀리면 연주 중 페이지가 밀리므로 반영 직전 상태를 스냅샷으로 남겨 한 번은 되돌릴 수 있게 함.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../cloud/api_client.dart';
import '../core/db/settings_repo.dart';
import 'page_render.dart';
import 'score_repo.dart';
import 'timeline.dart';

/// 되돌리기 스냅샷 키. 악보마다 마지막 한 번만 남김.
String _undoKey(int scoreId) => 'ai_undo_$scoreId';

/// 끝까지 받지 못한 분석 묶음의 키. 다시 누르면 같은 id로 보내 서버가 이미 뺀 코인과
/// 저장해 둔 결과를 이어받게 함.
String _batchKey(int scoreId) => 'ai_batch_$scoreId';

/// 템포 표기 음표의 길이(온음표 = 1). 이름은 서버 analyze.ts의 BpmUnitSchema와 같음.
const _noteLength = <String, double>{
  'whole': 1,
  'dotted_half': 3 / 4,
  'half': 1 / 2,
  'dotted_quarter': 3 / 8,
  'quarter': 1 / 4,
  'dotted_eighth': 3 / 16,
  'eighth': 1 / 8,
  'sixteenth': 1 / 16,
};

/// 악보에 적힌 템포를 앱의 클릭 템포(분당 클릭 수)로 바꿈. 클릭 하나는 한 마디(tsNum/tsDen)를
/// clicksPerBar로 나눈 길이라, 표기 음표와 클릭 음표의 길이 비만큼 곱함.
/// 2/2에 ♩=144면 2분음표 클릭 72, 6/8에 ♪=168이면 점4분 클릭 56이 됨.
/// 단위를 모르거나 결과가 다룰 수 있는 범위를 벗어나면 null이라 반영하지 않음.
double? clickBpmFromMarking(
  double marked,
  String? unit, {
  required int tsNum,
  required int tsDen,
  required int clicksPerBar,
}) {
  final noteLength = _noteLength[unit];
  if (noteLength == null || !marked.isFinite || marked <= 0) return null;
  if (tsNum <= 0 || tsDen <= 0 || clicksPerBar <= 0) return null;
  // 곱셈을 먼저 하고 한 번만 나눠 정수 템포가 소수 오차 없이 나오게 함
  final bpm = marked * noteLength * clicksPerBar * tsDen / tsNum;
  return bpm >= kMinBpm && bpm <= kMaxBpm ? bpm : null;
}

class AiApplyResult {
  /// 분석 반영 결과를 담음.
  const AiApplyResult({
    required this.appliedPages,
    required this.lowConfidence,
    required this.bpmApplied,
    required this.balance,
    required this.coinsSpent,
    this.missingPages = const [],
    this.partialReason,
  });

  final int appliedPages;
  final int lowConfidence;
  final bool bpmApplied;
  final int balance;
  final int coinsSpent;

  /// 보냈거나 보내려 했지만 결과가 없어 반영하지 못한 쪽(1부터). 모델이 빠뜨린 쪽과
  /// 그림으로 바꾸지 못한 쪽이 들어감. 끝까지 못 간 뒷부분은 [partialReason]이 따로 알림.
  final List<int> missingPages;

  /// 끝까지 못 가고 앞부분만 반영했을 때의 사유. 끝까지 갔으면 null.
  final String? partialReason;
}

class AiAnalysisService {
  /// 분석 서비스를 만듦. render는 테스트가 PDF 없이 쪽 그림을 넣을 때만 바꿈.
  AiAnalysisService(this._api, this._scores, this._settings, {this.render = renderPages});

  final ApiClient _api;
  final ScoreRepo _scores;
  final SettingsRepo _settings;

  /// 쪽들을 분석용 PNG로 굽는 함수.
  final Future<List<({int index, Uint8List png})>> Function(
    String pdfPath,
    List<int> indices,
    int width, {
    void Function(int done, int total)? onProgress,
  })
  render;

  /// 되돌릴 스냅샷이 남아 있는지.
  Future<bool> hasUndo(int scoreId) async => (await _settings.get(_undoKey(scoreId))) != null;

  /// 지금 설정을 되돌리기 지점으로 저장함. 값을 덮어쓰기 직전에 부름.
  /// 악보마다 한 지점만 남으므로 다시 부르면 이전 지점은 사라짐.
  Future<void> saveUndoPoint(int scoreId) async {
    final score = await _scores.score(scoreId);
    final pages = await _scores.pages(scoreId);
    if (score == null) return;
    await _settings.set(
      _undoKey(scoreId),
      jsonEncode({
        'bpm': score.bpm,
        'clicksPerBar': score.clicksPerBar,
        'timeSigNum': score.timeSigNum,
        'timeSigDen': score.timeSigDen,
        'bars': {for (final p in pages) '${p.pageIndex}': p.barCount},
      }),
    );
  }

  /// 스냅샷으로 되돌리고 스냅샷을 지움. 되돌릴 것이 없으면 false.
  Future<bool> undo(int scoreId) async {
    final raw = await _settings.get(_undoKey(scoreId));
    if (raw == null) return false;
    try {
      final snap = jsonDecode(raw) as Map<String, dynamic>;
      await _scores.updateSettings(
        scoreId,
        bpm: (snap['bpm'] as num).toDouble(),
        clicksPerBar: (snap['clicksPerBar'] as num).toInt(),
        timeSigNum: (snap['timeSigNum'] as num).toInt(),
        timeSigDen: (snap['timeSigDen'] as num).toInt(),
      );
      final bars = (snap['bars'] as Map).cast<String, dynamic>();
      for (final e in bars.entries) {
        await _scores.updatePage(scoreId, int.parse(e.key), barCount: (e.value as num).toInt());
      }
      await _settings.remove(_undoKey(scoreId));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 이어받을 분석 묶음 기록을 읽음. 없거나 깨졌거나 쪽수·나누는 단위가 다르면 null.
  Future<Map<String, dynamic>?> _savedBatch(int scoreId, int pageCount, int perCall) async {
    final raw = await _settings.get(_batchKey(scoreId));
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['pageCount'] == pageCount && saved['perCall'] == perCall && saved['id'] is String) {
        return saved;
      }
    } catch (_) {
      // 깨진 기록은 없는 것으로 봄. 다음 batchIdFor가 새 id로 덮음
    }
    return null;
  }

  /// 이 악보의 분석 묶음 id. 남은 묶음이 있으면 같은 id를 다시 쓰고, 없으면 새로 만들어 저장함.
  Future<String> batchIdFor(int scoreId, {required int pageCount, required int perCall}) async {
    // 같은 id로 보내야 서버가 이미 뺀 코인과 저장해 둔 결과를 이어받음
    final saved = await _savedBatch(scoreId, pageCount, perCall);
    if (saved != null) return saved['id'] as String;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    await _settings.set(
      _batchKey(scoreId),
      jsonEncode({'id': id, 'pageCount': pageCount, 'perCall': perCall}),
    );
    return id;
  }

  /// 남은 묶음 기록의 쪽 목록 key('answered' 결과 받음, 'sent' 보냄)에 쪽(0부터)을 더하거나(add) 뺌.
  /// 기록이 없으면 아무것도 안 함.
  Future<void> _markPages(
    int scoreId,
    int pageCount,
    int perCall,
    String key,
    Iterable<int> pages, {
    bool add = true,
  }) async {
    final saved = await _savedBatch(scoreId, pageCount, perCall);
    if (saved == null) return;
    final marked = _pagesIn(saved, key);
    add ? marked.addAll(pages) : marked.removeAll(pages);
    saved[key] = marked.toList()..sort();
    await _settings.set(_batchKey(scoreId), jsonEncode(saved));
  }

  /// 묶음 기록의 쪽 목록 key. 기록이 없거나 모양이 틀리면 빈 집합.
  Set<int> _pagesIn(Map<String, dynamic>? saved, String key) {
    final list = saved?[key];
    return list is List ? list.whereType<int>().toSet() : {};
  }

  /// 이번 분석에서 코인이 드는 쪽 수(charged)와 앞서 보냈지만 답을 못 받은 쪽 수(pending).
  /// 결과를 받은 쪽은 둘 다에서 뺌. pending은 서버에 결과가 남아 있으면 같은 id로 코인 없이 받고,
  /// 서버가 받지 못했으면 코인이 듦. 서버가 선점 뒤 환불했으면 환불과 재차감이 상쇄됨.
  Future<({int charged, int pending})> pagesToCharge(
    int scoreId, {
    required int pageCount,
    required int perCall,
  }) async {
    final saved = await _savedBatch(scoreId, pageCount, perCall);
    bool inRange(int i) => i >= 0 && i < pageCount;
    final answered = _pagesIn(saved, 'answered').where(inRange).toSet();
    final pending = _pagesIn(saved, 'sent').where(inRange).toSet().difference(answered).length;
    return (charged: pageCount - answered.length - pending, pending: pending);
  }

  /// 악보 전체를 묶음으로 나눠 분석하고 반영함. 보낸 쪽과 결과 받은 쪽을 묶음 기록에 남기고
  /// 끝까지 받으면 기록을 지움.
  /// cancel이 완료되면 다음 렌더·요청을 시작하지 않고, 아무것도 반영하지 않고 묶음 기록을 둔 채
  /// [AnalysisCancelled]를 던짐. 묶음 기록을 지우고 반영을 시작한 뒤의 멈춤은 받지 않음.
  Future<AiApplyResult> analyzeAndApply(
    String token, {
    required int scoreId,
    required String pdfPath,
    required int pageCount,
    required int maxPagesPerCall,
    void Function(String stage, int done, int total)? onProgress,
    Completer<void>? cancel,
  }) async {
    final responses = <ScoreAnalysis>[];
    final attempted = <int>[];
    var rendered = 0;
    String? partialReason;

    // 서버가 한 번에 받는 쪽수에 상한이 있어 나눠 보내며 코인도 묶음마다 빠짐. 묶음 id는 끝까지
    // 받았을 때만 지워, 중간에 끊겨 다시 눌러도 받은 묶음의 코인이 또 빠지지 않음
    final batchId = await batchIdFor(scoreId, pageCount: pageCount, perCall: maxPagesPerCall);

    // 묶음 단위로 렌더하고 보낸 뒤 버림. 전 쪽을 한 번에 올리면 60쪽짜리에서
    // PNG만 수백 MB가 되고 base64가 다시 1.33배를 얹어 태블릿이 죽음
    for (var from = 0; from < pageCount; from += maxPagesPerCall) {
      final to = (from + maxPagesPerCall).clamp(0, pageCount);
      onProgress?.call('render', rendered, pageCount);
      final chunk = await untilCancelled(
        () => render(
          pdfPath,
          [for (var i = from; i < to; i++) i],
          kAnalyzeWidth,
          onProgress: (done, _) => onProgress?.call('render', rendered + done, pageCount),
        ),
        cancel,
      );
      rendered = to;
      if (chunk.isEmpty) {
        if (responses.isEmpty && to >= pageCount) throw ApiException('악보를 그림으로 바꾸지 못함');
        attempted.addAll([for (var i = from; i < to; i++) i]);
        continue;
      }

      onProgress?.call('analyze', from, pageCount);
      // 빠진 쪽이 있는 묶음은 다시 보낼 때 그 쪽이 렌더되면 다른 id라 코인이 다시 듦.
      // 그래서 통째로 렌더된 묶음만 보냄·받음을 기록함
      final indices = [for (final c in chunk) c.index];
      final whole = chunk.length == to - from;
      // 보내기 전에 남김. 답을 못 받고 멈추거나 앱이 죽어도 다시 누를 때 이어받을 쪽으로 셈
      if (whole) await _markPages(scoreId, pageCount, maxPagesPerCall, 'sent', indices);
      try {
        final res = await _api.analyze(
          token,
          // 보내는 쪽 번호까지 id에 넣음. 다시 보낼 때 렌더 실패로 쪽 구성이 달라지면 다른 요청으로 셈
          requestId: '$batchId-${indices.join('.')}',
          pages: [for (final c in chunk) (index: c.index, png: c.png)],
          cancel: cancel,
        );
        responses.add(res);
        attempted.addAll([for (var i = from; i < to; i++) i]);
        if (whole) await _markPages(scoreId, pageCount, maxPagesPerCall, 'answered', indices);
      } catch (e) {
        // 재시도 대상이 아닌 거절(402, 502 환불 등)은 서버에 선점이 남지 않아 다시 보내면 코인이 듦
        if (whole && e is ApiException && !e.isRetryable) {
          await _markPages(scoreId, pageCount, maxPagesPerCall, 'sent', indices, add: false);
        }
        // 멈추면 받은 결과도 반영하지 않음. 묶음 기록이 남아 다시 누르면 같은 id로 코인 없이 받음.
        // 그 밖의 실패는 앞서 읽은 쪽을 살림. 이미 코인을 쓴 결과를 통째로 버리지 않음
        if (e is AnalysisCancelled || responses.isEmpty) rethrow;
        partialReason = '$e';
        break;
      }
    }

    // 마지막 응답 뒤 기록을 쓰는 사이에 멈췄을 수 있음. 여기서 받아야 묶음 기록이 남아 이어받을 수 있음.
    // 기록을 지운 뒤에 던지면 코인을 쓴 결과를 반영도 이어받기도 못함
    if (cancel?.isCompleted ?? false) throw const AnalysisCancelled();
    if (partialReason == null) await _settings.remove(_batchKey(scoreId));
    return applyAnalyses(
      scoreId,
      pageCount: pageCount,
      responses: responses,
      attempted: attempted,
      partialReason: partialReason,
    );
  }

  /// 받은 분석들을 합쳐 설정에 반영하고 반영 직전 상태를 되돌리기 지점으로 남김.
  /// 템포는 악보에 숫자로 적힌 표기만, 앱의 클릭 단위로 환산해 넣음. 용어만 보고 고른 값은
  /// 사용자가 맞춘 템포를 덮을 만큼 믿을 수 없음. attempted 중 결과가 없는 쪽은 missingPages로 알림.
  Future<AiApplyResult> applyAnalyses(
    int scoreId, {
    required int pageCount,
    required List<ScoreAnalysis> responses,
    required Iterable<int> attempted,
    String? partialReason,
  }) async {
    final results = [for (final r in responses) ...r.pages];
    final spent = responses.fold(0, (sum, r) => sum + r.coinsSpent);
    final balance = responses.isEmpty ? 0 : responses.last.balance;

    // 아무것도 못 읽었으면 되돌리기 지점을 덮지 않음. 덮으면 이전 지점이 사라짐
    if (results.isEmpty) {
      return AiApplyResult(
        appliedPages: 0,
        lowConfidence: 0,
        bpmApplied: false,
        balance: balance,
        coinsSpent: spent,
        partialReason: partialReason ?? '읽어 낸 쪽이 없음',
      );
    }

    await saveUndoPoint(scoreId);

    final applied = <int>{};
    for (final p in results) {
      final index = p.page - 1;
      // 표지처럼 연주가 없는 쪽은 0마디가 맞음. 음수만 걸러 냄
      if (index < 0 || index >= pageCount || p.bars < 0 || applied.contains(index)) continue;
      await _scores.updatePage(scoreId, index, barCount: p.bars);
      applied.add(index);
    }

    // 박자표는 앞쪽 묶음에서 먼저 읽힌 값을 씀. 보통 첫 쪽에만 적혀 있음
    final ts = responses
        .where((r) => (r.timeSigNum ?? 0) > 0 && (r.timeSigDen ?? 0) > 0)
        .map((r) => (num: r.timeSigNum!, den: r.timeSigDen!))
        .firstOrNull;
    final marking = responses.where((r) => r.bpmSource == 'marking' && r.bpm != null).firstOrNull;

    // 템포는 반영될 박자표와 클릭 수 기준으로 환산함. 박자표를 못 읽었으면 지금 설정을 기준으로 함
    double? bpm;
    final score = await _scores.score(scoreId);
    if (marking != null && (ts != null || score != null)) {
      bpm = clickBpmFromMarking(
        marking.bpm!,
        marking.bpmUnit,
        tsNum: ts?.num ?? score!.timeSigNum,
        tsDen: ts?.den ?? score!.timeSigDen,
        clicksPerBar: ts != null ? defaultClicksPerBar(ts.num, ts.den) : score!.clicksPerBar,
      );
    }
    if (bpm != null || ts != null) {
      await _scores.updateSettings(
        scoreId,
        bpm: bpm,
        timeSigNum: ts?.num,
        timeSigDen: ts?.den,
        clicksPerBar: ts != null ? defaultClicksPerBar(ts.num, ts.den) : null,
      );
    }

    return AiApplyResult(
      appliedPages: applied.length,
      lowConfidence: results.where((p) => p.confidence == 'low').length,
      bpmApplied: bpm != null,
      balance: balance,
      coinsSpent: spent,
      missingPages: [
        for (final i in attempted.toSet().toList()..sort())
          if (!applied.contains(i)) i + 1,
      ],
      partialReason: partialReason,
    );
  }
}
