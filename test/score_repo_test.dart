// 악보 설정 저장과 타임라인 입력 변환 검증. 잘못된 재생 순서 하나가 재생 중 범위 밖 접근으로
// 앱을 죽이므로 방어 경로를 특히 고정해 둠.

import 'package:baton/core/db/database.dart';
import 'package:baton/reader/annotation/stroke.dart';
import 'package:baton/score/score_repo.dart';
import 'package:baton/score/timeline.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BatonDatabase db;
  late ScoreRepo repo;

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    repo = ScoreRepo(db);
  });

  tearDown(() => db.close());

  Future<int> makeScore({int pages = 3}) => repo.createScore(name: '테스트 악보', pageCount: pages);

  test('악보를 만들면 페이지 행이 함께 생김', () async {
    final id = await makeScore(pages: 4);
    final ps = await repo.pages(id);
    expect(ps.length, 4);
    expect(ps.map((p) => p.pageIndex), [0, 1, 2, 3]);
    expect((await repo.score(id))!.bpm, 120);
    expect((await repo.score(id))!.fileRel, 'scores/$id/source.pdf', reason: '경로는 nodeId에서 유도됨');
  });

  test('타임라인 입력으로 변환됨', () async {
    final id = await makeScore(pages: 2);
    await repo.updateSettings(id, bpm: 90, clicksPerBar: 3, countInBars: 2, leadBeats: 1);
    await repo.updatePage(id, 0, barCount: 8);
    await repo.updatePage(id, 1, barCount: 6, bpm: const Value(60));

    final t = (await repo.playback(id))!.timing;
    expect(t.bpm, 90);
    expect(t.clicksPerBar, 3);
    expect(t.countInBars, 2);
    expect(t.leadBeats, 1);
    expect(t.pages.map((p) => p.barCount), [8, 6]);
    expect(t.pages[0].bpm, isNull, reason: '오버라이드 없으면 상속');
    expect(t.pages[1].bpm, 60);
  });

  test('오버라이드를 지우면 다시 상속함', () async {
    final id = await makeScore(pages: 1);
    await repo.updatePage(id, 0, bpm: const Value(200), clicksPerBar: const Value(7));
    expect((await repo.playback(id))!.timing.pages[0].bpm, 200);
    await repo.updatePage(id, 0, bpm: const Value(null), clicksPerBar: const Value(null));
    final t = (await repo.playback(id))!.timing;
    expect(t.pages[0].bpm, isNull);
    expect(t.pages[0].clicksPerBar, isNull);
  });

  test('전체 마디수를 균등 배분하고 나머지는 앞 페이지에 얹음', () async {
    final id = await makeScore(pages: 4);
    await repo.distributeBars(id, 10);
    expect((await repo.pages(id)).map((p) => p.barCount), [3, 3, 2, 2]);
  });

  test('균등 배분은 숨긴 쪽과 0마디 쪽을 빼고 표시 순서 앞쪽부터 나머지를 줌', () async {
    final id = await makeScore(pages: 5);
    await repo.updatePage(id, 0, barCount: 7);
    await repo.updatePage(id, 2, barCount: 0);
    // 0쪽·3쪽은 숨김, 2쪽은 표지라 0마디
    await repo.setPageOrder(id, [4, 1, 2]);
    await repo.distributeBars(id, 9);
    expect((await repo.pages(id)).map((p) => p.barCount), [7, 4, 0, 4, 5]);

    final pb = (await repo.playback(id))!;
    final played = pb.timing.pages.fold<int>(0, (sum, p) => sum + p.barCount);
    expect(played, 9, reason: '재생되는 마디 합이 입력값과 같아야 넘김이 앞서지 않음');
  });

  test('보이는 쪽이 전부 0마디면 보이는 쪽 전부에 나눔', () {
    final zero = [
      for (var i = 0; i < 3; i++)
        ScorePage(scoreId: 1, pageIndex: i, barCount: 0, bpm: null, clicksPerBar: null),
    ];
    expect(barDistributionTargets([2, 0], zero), [2, 0]);
  });

  test('쪽 템포 입력은 바꾼 항목만 쓰고 곡 설정과 같게 바꾸면 고정을 품', () {
    expect(pageOverride(120, shown: 120, inherited: 120).present, isFalse, reason: '손대지 않음');
    final same = pageOverride(96, shown: 100, inherited: 96);
    expect(same.present && same.value == null, isTrue, reason: '곡 설정으로 되돌림');
    expect(pageOverride(3, shown: 4, inherited: 4).value, 3);
  });

  test('박만 바꾼 쪽은 뒤에 곡 템포를 바꾸면 새 템포를 따라감', () async {
    final id = await makeScore(pages: 2);
    final s = (await repo.score(id))!;
    await repo.updatePage(
      id,
      0,
      bpm: pageOverride(120.0, shown: s.bpm.round(), inherited: s.bpm),
      clicksPerBar: pageOverride(3, shown: s.clicksPerBar, inherited: s.clicksPerBar),
    );
    await repo.updateSettings(id, bpm: 90);

    final t = (await repo.playback(id))!.timing;
    expect(t.pages[0].bpm, isNull);
    expect(t.pages[0].clicksPerBar, 3);
    expect(buildTimeline(t).spans.first.bpm, 90);
  });

  test('쪽 템포와 박 고정은 따로 풂', () async {
    final id = await makeScore(pages: 1);
    await repo.updatePage(id, 0, bpm: const Value(140), clicksPerBar: const Value(3));
    await repo.updatePage(id, 0, bpm: const Value(null));
    final p = (await repo.pages(id)).single;
    expect(p.bpm, isNull);
    expect(p.clicksPerBar, 3);
  });

  test('재생 순서를 저장하고 읽음', () async {
    final id = await makeScore(pages: 3);
    await repo.setPlayOrder(id, [0, 1, 1, 2]);
    expect((await repo.playback(id))!.timing.playOrder, [0, 1, 1, 2]);
    await repo.setPlayOrder(id, null);
    expect((await repo.playback(id))!.timing.playOrder, isNull);
  });

  test('범위를 벗어난 재생 순서는 선형으로 되돌림', () {
    expect(parsePlayOrder('[0,1,9]', 3), isNull, reason: '9는 범위 밖');
    expect(parsePlayOrder('[-1]', 3), isNull);
    expect(parsePlayOrder('[]', 3), isNull);
    expect(parsePlayOrder('망가진 json', 3), isNull);
    expect(parsePlayOrder('[0,"1"]', 3), isNull, reason: '정수가 아님');
    expect(parsePlayOrder('[2,0,1]', 3), [2, 0, 1]);
  });

  test('필기를 저장하고 읽음', () async {
    final id = await makeScore(pages: 2);
    final s = Stroke(
      tool: StrokeTool.pen,
      color: 0xFF112233,
      width: 0.003,
      points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
    );
    await repo.saveStrokes(id, 1, [s]);
    final back = await repo.strokes(id, 1);
    expect(back.length, 1);
    expect(back.first.color, 0xFF112233);
    expect(await repo.strokes(id, 0), isEmpty);
  });

  test('필기를 비우면 행이 사라짐', () async {
    final id = await makeScore(pages: 1);
    await repo.saveStrokes(id, 0, [
      Stroke(tool: StrokeTool.pen, color: 0, width: 0.002, points: const [Offset(0, 0)]),
    ]);
    await repo.saveStrokes(id, 0, []);
    expect(await repo.strokes(id, 0), isEmpty);
    expect(await db.select(db.annotations).get(), isEmpty);
  });

  test('페이지 수를 늘리면 행이 채워지고 줄이면 잘림', () async {
    final id = await makeScore(pages: 2);
    await repo.setPageCount(id, 5);
    expect((await repo.pages(id)).map((p) => p.pageIndex), [0, 1, 2, 3, 4]);
    expect((await repo.score(id))!.pageCount, 5);

    await repo.setPageCount(id, 3);
    expect((await repo.pages(id)).map((p) => p.pageIndex), [0, 1, 2]);
    expect((await repo.score(id))!.pageCount, 3);
  });

  test('페이지 수를 줄여도 남은 페이지의 마디수는 보존됨', () async {
    final id = await makeScore(pages: 3);
    await repo.updatePage(id, 0, barCount: 9);
    await repo.setPageCount(id, 2);
    expect((await repo.pages(id)).first.barCount, 9);
  });

  test('악보를 지우면 페이지와 필기도 함께 사라짐', () async {
    final id = await makeScore(pages: 2);
    await repo.saveStrokes(id, 0, [
      Stroke(
        tool: StrokeTool.pen,
        color: 0,
        width: 0.002,
        points: const [Offset(0, 0), Offset(1, 1)],
      ),
    ]);
    await repo.deleteScore(id);
    expect(await repo.score(id), isNull);
    expect(await db.select(db.scorePages).get(), isEmpty);
    expect(await db.select(db.annotations).get(), isEmpty);
  });

  test('표시 순서는 중복·범위 밖·빈 값을 원래 순서로 되돌림', () {
    expect(parsePageOrder(null, 3), [0, 1, 2]);
    expect(parsePageOrder('[2,0]', 3), [2, 0], reason: '일부만 보여도 됨');
    expect(parsePageOrder('[0,0,1]', 3), [0, 1, 2], reason: '표시 순서에 중복은 없음');
    expect(parsePageOrder('[0,5]', 3), [0, 1, 2]);
    expect(parsePageOrder('[]', 3), [0, 1, 2], reason: '전부 숨기면 볼 것이 없음');
    expect(parsePageOrder('깨짐', 3), [0, 1, 2]);
  });

  test('반복 횟수와 재생 순서가 서로 변환됨', () {
    expect(playOrderFromRepeats([1, 1, 1]), isNull, reason: '전부 1회면 선형');
    expect(playOrderFromRepeats([1, 2, 1]), [0, 1, 1, 2]);
    expect(repeatsFromPlayOrder([0, 1, 1, 2], 3), [1, 2, 1]);
    expect(repeatsFromPlayOrder(null, 3), [1, 1, 1]);
    expect(repeatsFromPlayOrder([2, 0, 1], 3), [
      1,
      1,
      1,
    ], reason: '되돌아가는 순서는 반복으로 담기지 않으므로 1회로 떨어뜨림');
  });

  test('재생 정보는 숨긴 페이지를 빼고 표시 순서를 따름', () async {
    final id = await makeScore(pages: 3);
    await repo.updatePage(id, 0, barCount: 1);
    await repo.updatePage(id, 1, barCount: 2);
    await repo.updatePage(id, 2, barCount: 3);
    await repo.setPageOrder(id, [2, 0]);

    final pb = (await repo.playback(id))!;
    expect(pb.pageOrder, [2, 0]);
    expect(pb.timing.pages.map((p) => p.barCount), [3, 1], reason: '1번 페이지는 숨김');
  });

  test('재생 순서는 표시 순서 위의 위치를 가리킴', () async {
    final id = await makeScore(pages: 3);
    await repo.setPageOrder(id, [2, 0]);
    await repo.setPlayOrder(id, [0, 1, 1]);
    final pb = (await repo.playback(id))!;
    expect(pb.timing.playOrder, [0, 1, 1]);
    // 표시 두 장뿐이므로 2를 가리키는 순서는 무효가 되어야 함
    await repo.setPlayOrder(id, [0, 2]);
    expect((await repo.playback(id))!.timing.playOrder, isNull);
  });

  test('깨진 획 하나 때문에 페이지 전체를 잃지 않음', () {
    final list = decodeStrokes('[{"t":0,"c":1,"w":0.1,"p":[0,0]},{"쓰레기":true}]');
    expect(list.length, 1);
    expect(decodeStrokes('not json'), isEmpty);
  });

  group('재생 설정 미설정 판정', () {
    /// 기본값이 4마디·120BPM이라 그대로 재생하면 쪽당 8초로 넘어감.
    /// 사용자가 "설정한 값"과 "손대지 않은 값"을 구분할 수 있어야 첫 사용에서 헤매지 않음.
    test('임포트 직후에는 미설정', () async {
      final id = await makeScore();
      final pb = await repo.playback(id);
      expect(pb!.timingUnset, isTrue);
    });

    test('한 쪽 마디수만 바꿔도 설정됨으로 봄', () async {
      final id = await makeScore();
      await repo.updatePage(id, 1, barCount: 8);
      expect((await repo.playback(id))!.timingUnset, isFalse);
    });

    test('템포만 바꿔도 설정됨으로 봄', () async {
      final id = await makeScore();
      await repo.updateSettings(id, bpm: 96);
      expect((await repo.playback(id))!.timingUnset, isFalse);
    });

    test('표시 순서만 바꿔도 설정됨으로 봄', () async {
      final id = await makeScore();
      await repo.setPageOrder(id, [2, 0, 1]);
      expect((await repo.playback(id))!.timingUnset, isFalse);
    });

    test('페이지 오버라이드만 있어도 설정됨으로 봄', () async {
      final id = await makeScore();
      await repo.updatePage(id, 0, bpm: const Value(140));
      expect((await repo.playback(id))!.timingUnset, isFalse);
    });
  });
}
