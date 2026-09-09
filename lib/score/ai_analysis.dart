// 악보를 서버에 보내 쪽별 마디수와 템포를 받아 설정에 반영함.
// 추정이 틀리면 연주 중 페이지가 밀리므로 반영 직전 상태를 스냅샷으로 남겨 한 번은 되돌릴 수 있게 함.

import 'dart:convert';
import 'dart:math';

import '../cloud/api_client.dart';
import '../core/db/settings_repo.dart';
import 'page_render.dart';
import 'score_repo.dart';
import 'timeline.dart';

/// 되돌리기 스냅샷 키. 악보마다 마지막 한 번만 남김.
String _undoKey(int scoreId) => 'ai_undo_$scoreId';

class AiApplyResult {
  const AiApplyResult({
    required this.appliedPages,
    required this.lowConfidence,
    required this.bpmApplied,
    required this.balance,
    required this.coinsSpent,
    this.partialReason,
  });

  final int appliedPages;
  final int lowConfidence;
  final bool bpmApplied;
  final int balance;
  final int coinsSpent;

  /// 끝까지 못 가고 앞부분만 반영했을 때의 사유. 끝까지 갔으면 null.
  final String? partialReason;
}

class AiAnalysisService {
  AiAnalysisService(this._api, this._scores, this._settings);

  final ApiClient _api;
  final ScoreRepo _scores;
  final SettingsRepo _settings;

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

  /// 악보 전체를 분석해 설정에 반영함.
  /// 서버가 한 번에 받는 쪽수에 상한이 있어 나눠 보내며, 코인도 묶음마다 빠짐.
  Future<AiApplyResult> analyzeAndApply(
    String token, {
    required int scoreId,
    required String pdfPath,
    required int pageCount,
    required int maxPagesPerCall,
    void Function(String stage, int done, int total)? onProgress,
  }) async {
    final results = <PageAnalysis>[];
    double? bpm;
    String bpmSource = 'none';
    int? tsNum;
    int? tsDen;
    var spent = 0;
    var balance = 0;
    var rendered = 0;
    String? partialReason;

    // 재시도를 구분할 열쇠. 묶음마다 달라야 하고, 같은 묶음을 다시 보낼 때는 같아야 함
    final batchId = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

    // 묶음 단위로 렌더하고 보낸 뒤 버림. 전 쪽을 한 번에 올리면 60쪽짜리에서
    // PNG만 수백 MB가 되고 base64가 다시 1.33배를 얹어 태블릿이 죽음
    for (var from = 0; from < pageCount; from += maxPagesPerCall) {
      final to = (from + maxPagesPerCall).clamp(0, pageCount);
      onProgress?.call('render', rendered, pageCount);
      final chunk = await renderPages(
        pdfPath,
        [for (var i = from; i < to; i++) i],
        kAnalyzeWidth,
        onProgress: (done, _) => onProgress?.call('render', rendered + done, pageCount),
      );
      rendered = to;
      if (chunk.isEmpty) {
        if (results.isEmpty && to >= pageCount) throw ApiException('악보를 그림으로 바꾸지 못함');
        continue;
      }

      onProgress?.call('analyze', from, pageCount);
      try {
        final res = await _api.analyze(
          token,
          requestId: '$batchId-$from',
          pages: [for (final c in chunk) (index: c.index, png: c.png)],
        );
        results.addAll(res.pages);
        spent += res.coinsSpent;
        balance = res.balance;
        if (bpm == null && res.bpm != null) {
          bpm = res.bpm;
          bpmSource = res.bpmSource;
        }
        tsNum ??= res.timeSigNum;
        tsDen ??= res.timeSigDen;
      } catch (e) {
        // 묶음 하나가 실패해도 앞서 읽은 쪽은 살림. 이미 코인을 쓴 결과를 통째로 버리지 않음
        if (results.isEmpty) rethrow;
        partialReason = '$e';
        break;
      }
    }

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

    var applied = 0;
    for (final p in results) {
      final index = p.page - 1;
      // 표지처럼 연주가 없는 쪽은 0마디가 맞음. 음수만 걸러 냄
      if (index < 0 || index >= pageCount || p.bars < 0) continue;
      await _scores.updatePage(scoreId, index, barCount: p.bars);
      applied++;
    }

    // 표기가 없어 지어낸 값은 반영하지 않음. 사용자가 직접 넣는 편이 안전함
    final bpmApplied = bpm != null && bpmSource != 'none';
    if (bpmApplied || (tsNum != null && tsDen != null)) {
      await _scores.updateSettings(
        scoreId,
        bpm: bpmApplied ? bpm : null,
        timeSigNum: tsNum,
        timeSigDen: tsDen,
        clicksPerBar: tsNum != null && tsDen != null ? defaultClicksPerBar(tsNum, tsDen) : null,
      );
    }

    return AiApplyResult(
      appliedPages: applied,
      lowConfidence: results.where((p) => p.confidence == 'low').length,
      bpmApplied: bpmApplied,
      balance: balance,
      coinsSpent: spent,
      partialReason: partialReason,
    );
  }
}
