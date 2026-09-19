// 악보 재생 설정과 페이지·필기의 저장·조회. DB 행을 타임라인 입력으로 옮기는 지점이기도 함.
// 파일 자체는 다루지 않음. 경로 규칙은 core/storage/paths.dart가 소유함.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/db/database.dart';
import '../core/db/tables.dart';
import '../core/storage/paths.dart';
import '../reader/annotation/stroke.dart';
import 'page_rotation.dart';
import 'timeline.dart';

class ScoreRepo {
  ScoreRepo(this.db);

  final BatonDatabase db;

  /// 악보 노드와 재생 설정, 페이지 행을 한 트랜잭션으로 만듦. 노드 id를 돌려줌.
  /// 파일 경로는 nodeId에서 유도하므로 호출자가 넘기지 않음.
  Future<int> createScore({
    required String name,
    required int pageCount,
    int? parentId,
  }) => db.transaction(() async {
    final id = await db
        .into(db.nodes)
        .insert(NodesCompanion.insert(kind: NodeKind.score, name: name, parentId: Value(parentId)));
    await db
        .into(db.scores)
        .insert(
          ScoresCompanion.insert(
            nodeId: Value(id),
            fileRel: AppPaths.sourcePdf(id),
            pageCount: pageCount,
          ),
        );
    await db.batch((b) {
      b.insertAll(db.scorePages, [
        for (var i = 0; i < pageCount; i++) ScorePagesCompanion.insert(scoreId: id, pageIndex: i),
      ]);
    });
    return id;
  });

  /// 실제 PDF에서 읽은 페이지 수로 맞추고 페이지 행을 그 수에 맞춰 채우거나 잘라냄.
  /// 임포트 직후 한 번 부름.
  Future<void> setPageCount(int id, int count) => db.transaction(() async {
    await (db.update(
      db.scores,
    )..where((s) => s.nodeId.equals(id))).write(ScoresCompanion(pageCount: Value(count)));
    final existing = await pages(id);
    if (existing.length < count) {
      await db.batch((b) {
        b.insertAll(db.scorePages, [
          for (var i = existing.length; i < count; i++)
            ScorePagesCompanion.insert(scoreId: id, pageIndex: i),
        ]);
      });
    } else if (existing.length > count) {
      await (db.delete(
        db.scorePages,
      )..where((p) => p.scoreId.equals(id) & p.pageIndex.isBiggerOrEqualValue(count))).go();
      // 남겨 두면 나중에 쪽수가 다시 늘 때 옛 필기가 엉뚱한 페이지에 되살아남
      await (db.delete(
        db.annotations,
      )..where((a) => a.scoreId.equals(id) & a.pageIndex.isBiggerOrEqualValue(count))).go();
      // 범위를 벗어난 순서는 읽을 때 폴백되지만, 남겨 두면 사용자가 지정한 순서가
      // 조용히 무시되는 상태로 남으므로 여기서 비움
      await (db.update(db.scores)..where((s) => s.nodeId.equals(id))).write(
        const ScoresCompanion(pageOrderJson: Value(null), playOrderJson: Value(null)),
      );
    }
  });

  /// 악보 노드를 완전히 지움. 페이지·필기는 외래키 cascade로 함께 사라짐.
  /// 파일 삭제는 호출자 몫.
  Future<void> deleteScore(int id) async {
    await (db.delete(db.nodes)..where((n) => n.id.equals(id))).go();
  }

  /// 악보 설정 행. 없으면 null.
  Future<Score?> score(int id) =>
      (db.select(db.scores)..where((s) => s.nodeId.equals(id))).getSingleOrNull();

  /// 페이지 행을 pageIndex 순서로.
  Future<List<ScorePage>> pages(int id) =>
      (db.select(db.scorePages)
            ..where((p) => p.scoreId.equals(id))
            ..orderBy([(p) => OrderingTerm(expression: p.pageIndex)]))
          .get();

  /// 재생에 필요한 것을 한 번에 읽음. 숨긴 페이지를 빼고 표시 순서대로 정렬해서 돌려줌.
  Future<ScorePlayback?> playback(int id) async {
    final s = await score(id);
    if (s == null) return null;
    final ps = await pages(id);
    final order = parsePageOrder(s.pageOrderJson, ps.length);
    final visible = [for (final i in order) ps[i]];
    return ScorePlayback(
      timing: ScoreTiming(
        bpm: s.bpm,
        clicksPerBar: s.clicksPerBar,
        countInBars: s.countInBars,
        leadBeats: s.leadBeats,
        pages: [
          for (final p in visible)
            PageTiming(barCount: p.barCount, bpm: p.bpm, clicksPerBar: p.clicksPerBar),
        ],
        playOrder: parsePlayOrder(s.playOrderJson, visible.length),
      ),
      pageOrder: order,
      timingUnset: isTimingUnset(s, ps),
    );
  }

  /// 화면에 보여줄 페이지 순서를 저장함. null이면 원래 순서로 되돌림.
  Future<void> setPageOrder(int scoreId, List<int>? order) async {
    await (db.update(db.scores)..where((s) => s.nodeId.equals(scoreId))).write(
      ScoresCompanion(pageOrderJson: Value(order == null ? null : jsonEncode(order))),
    );
  }

  /// 악보 전체 설정을 갱신함. null 인자는 건드리지 않음.
  Future<void> updateSettings(
    int id, {
    double? bpm,
    int? timeSigNum,
    int? timeSigDen,
    int? clicksPerBar,
    int? countInBars,
    double? leadBeats,
    String? composer,
    String? memo,
  }) async {
    await (db.update(db.scores)..where((s) => s.nodeId.equals(id))).write(
      ScoresCompanion(
        bpm: bpm == null ? const Value.absent() : Value(bpm),
        timeSigNum: timeSigNum == null ? const Value.absent() : Value(timeSigNum),
        timeSigDen: timeSigDen == null ? const Value.absent() : Value(timeSigDen),
        clicksPerBar: clicksPerBar == null ? const Value.absent() : Value(clicksPerBar),
        countInBars: countInBars == null ? const Value.absent() : Value(countInBars),
        leadBeats: leadBeats == null ? const Value.absent() : Value(leadBeats),
        composer: composer == null ? const Value.absent() : Value(composer),
        memo: memo == null ? const Value.absent() : Value(memo),
      ),
    );
  }

  /// 페이지 한 장의 타이밍을 갱신함. 빠진 인자는 건드리지 않음.
  /// bpm·clicksPerBar는 따로 다룸. Value(null)을 넣은 항목만 오버라이드를 풀고 악보 기본값을 상속함.
  Future<void> updatePage(
    int scoreId,
    int pageIndex, {
    int? barCount,
    Value<double?> bpm = const Value.absent(),
    Value<int?> clicksPerBar = const Value.absent(),
  }) async {
    await (db.update(
      db.scorePages,
    )..where((p) => p.scoreId.equals(scoreId) & p.pageIndex.equals(pageIndex))).write(
      ScorePagesCompanion(
        barCount: barCount == null ? const Value.absent() : Value(barCount),
        bpm: bpm,
        clicksPerBar: clicksPerBar,
      ),
    );
  }

  /// 곡 전체 마디수를 barDistributionTargets가 고른 쪽에 균등 배분함.
  /// 나머지는 표시 순서 앞쪽부터 한 마디씩 더 줌. 대상이 아닌 쪽의 마디수는 건드리지 않음.
  Future<void> distributeBars(int scoreId, int totalBars) async {
    final s = await score(scoreId);
    if (s == null || totalBars <= 0) return;
    final ps = await pages(scoreId);
    final targets = barDistributionTargets(parsePageOrder(s.pageOrderJson, ps.length), ps);
    if (targets.isEmpty) return;
    final base = totalBars ~/ targets.length;
    final extra = totalBars % targets.length;
    await db.batch((b) {
      for (var k = 0; k < targets.length; k++) {
        b.update(
          db.scorePages,
          ScorePagesCompanion(barCount: Value(base + (k < extra ? 1 : 0))),
          where: (p) => p.scoreId.equals(scoreId) & p.pageIndex.equals(targets[k]),
        );
      }
    });
  }

  /// 재생 순서를 저장함. null이면 선형으로 되돌림.
  Future<void> setPlayOrder(int scoreId, List<int>? order) async {
    await (db.update(db.scores)..where((s) => s.nodeId.equals(scoreId))).write(
      ScoresCompanion(playOrderJson: Value(order == null ? null : jsonEncode(order))),
    );
  }

  /// 페이지를 시계방향으로 90도씩 돌림. PDF에 구우고 그 페이지의 필기도 같은 각도로 돌림.
  /// 둘을 함께 바꾸지 않으면 필기가 악보와 어긋난 채 남음.
  Future<void> rotatePage(int scoreId, int pageIndex, int quarterTurns) async {
    final turns = quarterTurns & 3;
    if (turns == 0) return;
    final s = await score(scoreId);
    if (s == null) return;
    final path = AppPaths.abs(s.fileRel);

    final aspect = await pageAspect(path, pageIndex);
    final marks = await strokes(scoreId, pageIndex);
    await rotatePdfPage(path, pageIndex, turns);
    if (marks.isEmpty) return;
    await saveStrokes(scoreId, pageIndex, [for (final m in marks) rotateStroke(m, turns, aspect)]);
  }

  /// 페이지 필기를 읽음. 없으면 빈 목록.
  Future<List<Stroke>> strokes(int scoreId, int pageIndex) async {
    final row = await (db.select(
      db.annotations,
    )..where((a) => a.scoreId.equals(scoreId) & a.pageIndex.equals(pageIndex))).getSingleOrNull();
    if (row == null) return [];
    return decodeStrokes(row.strokesJson);
  }

  /// 페이지 필기를 통째로 덮어씀. 비면 행을 지워 DB가 커지지 않게 함.
  Future<void> saveStrokes(int scoreId, int pageIndex, List<Stroke> strokes) async {
    if (strokes.isEmpty) {
      await (db.delete(
        db.annotations,
      )..where((a) => a.scoreId.equals(scoreId) & a.pageIndex.equals(pageIndex))).go();
      return;
    }
    await db
        .into(db.annotations)
        .insertOnConflictUpdate(
          AnnotationsCompanion.insert(
            scoreId: scoreId,
            pageIndex: pageIndex,
            strokesJson: jsonEncode([for (final s in strokes) s.toJson()]),
          ),
        );
  }
}

/// 화면 표시 순서를 검증하며 읽음. 중복이나 범위 밖 값이 섞이면 원래 순서로 되돌림.
/// 전부 숨기면 볼 것이 없어지므로 빈 배열도 되돌림.
List<int> parsePageOrder(String? json, int pageCount) {
  final fallback = List<int>.generate(pageCount, (i) => i);
  if (json == null || pageCount == 0) return fallback;
  try {
    final raw = jsonDecode(json);
    if (raw is! List || raw.isEmpty) return fallback;
    final seen = <int>{};
    final out = <int>[];
    for (final v in raw) {
      if (v is! int || v < 0 || v >= pageCount || !seen.add(v)) return fallback;
      out.add(v);
    }
    return out;
  } catch (_) {
    return fallback;
  }
}

/// 균등 배분 대상 쪽의 물리 인덱스를 표시 순서대로 고름. 숨긴 쪽은 재생되지 않으므로 뺌.
/// 0마디로 둔 쪽(표지·해설)도 뺌. 보이는 쪽이 전부 0마디면 뺄 기준이 없어 전부 돌려줌.
List<int> barDistributionTargets(List<int> order, List<ScorePage> pages) {
  final counted = [
    for (final i in order)
      if (pages[i].barCount > 0) i,
  ];
  return counted.isEmpty ? order : counted;
}

/// 쪽 템포·박 입력 하나를 저장할 값으로 바꿈. 보여 준 값 그대로면 건드리지 않고(absent),
/// 악보 기본값과 같게 바꾸면 오버라이드를 풀어(null) 이후 전체 템포·박 변경을 따라가게 함.
Value<T?> pageOverride<T extends num>(T entered, {required num shown, required num inherited}) =>
    entered == shown ? const Value.absent() : Value(entered == inherited ? null : entered);

/// 재생과 표시에 필요한 것을 함께 담음. pageOrder는 표시 인덱스에서 물리 페이지로 가는 지도.
class ScorePlayback {
  const ScorePlayback({required this.timing, required this.pageOrder, required this.timingUnset});

  final ScoreTiming timing;
  final List<int> pageOrder;

  /// 재생 설정을 한 번도 손대지 않았는지. 리더가 안내를 띄울지 판단하는 데 씀.
  final bool timingUnset;
}

/// 재생 설정이 임포트 직후 모습 그대로인지. 한 군데라도 손대면 false.
/// 기본값이 4마디·120BPM이라 그대로 재생하면 쪽당 8초로 넘어가는데, 사용자는 그것이
/// 설정된 값인지 손대지 않은 값인지 화면에서 구분할 수 없음. 그 구분을 여기서 만듦.
/// ponytail: 컬럼을 늘리지 않고 기본값에서 유도함. 진짜로 전 쪽이 4마디·120BPM인 악보는
/// 오탐이지만 대가가 안내 칩 한 번이라 감수함. 다른 이유로 스키마를 올릴 일이 생기면 컬럼으로 승격.
bool isTimingUnset(Score s, List<ScorePage> pages) =>
    s.bpm == 120 &&
    s.clicksPerBar == 4 &&
    s.timeSigNum == 4 &&
    s.timeSigDen == 4 &&
    s.pageOrderJson == null &&
    s.playOrderJson == null &&
    pages.every((p) => p.barCount == 4 && p.bpm == null && p.clicksPerBar == null);

/// 저장된 재생 순서를 검증하며 읽음. 비었거나 범위를 벗어난 값이 섞이면 선형으로 되돌림.
/// 잘못된 인덱스 하나가 재생 중 범위 밖 접근으로 앱을 죽이므로 여기서 막음.
List<int>? parsePlayOrder(String? json, int pageCount) {
  if (json == null || pageCount == 0) return null;
  try {
    final raw = jsonDecode(json);
    if (raw is! List || raw.isEmpty) return null;
    final order = <int>[];
    for (final v in raw) {
      if (v is! int || v < 0 || v >= pageCount) return null;
      order.add(v);
    }
    return order;
  } catch (_) {
    return null;
  }
}

/// 저장된 필기 JSON을 읽음. 깨진 항목은 건너뛰어 한 획 때문에 페이지 전체를 잃지 않게 함.
List<Stroke> decodeStrokes(String json) {
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return [];
    final out = <Stroke>[];
    for (final e in raw) {
      try {
        out.add(Stroke.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// 재생 순서를 페이지별 반복 횟수로 바꿈. 연속으로 같은 값이 이어지면 반복으로 봄.
/// D.S. 같은 되돌아가기는 이 표현으로 담기지 않으므로 그런 순서는 반복 1로 떨어뜨림.
List<int> repeatsFromPlayOrder(List<int>? playOrder, int pageCount) {
  final flat = List<int>.filled(pageCount, 1);
  if (playOrder == null || playOrder.isEmpty) return flat;
  var i = 0;
  var slot = 0;
  while (i < playOrder.length && slot < pageCount) {
    if (playOrder[i] != slot) return flat;
    var n = 0;
    while (i < playOrder.length && playOrder[i] == slot) {
      n++;
      i++;
    }
    flat[slot] = n.clamp(1, 9);
    slot++;
  }
  return flat;
}

/// 페이지별 반복 횟수를 재생 순서로 펼침. 전부 1회면 선형이므로 null.
List<int>? playOrderFromRepeats(List<int> repeats) {
  if (repeats.every((r) => r <= 1)) return null;
  final out = <int>[];
  for (var i = 0; i < repeats.length; i++) {
    for (var r = 0; r < repeats[i].clamp(1, 9); r++) {
      out.add(i);
    }
  }
  return out;
}
