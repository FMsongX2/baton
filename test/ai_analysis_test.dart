// AI 반영 되돌리기 검증. 잘못 읽은 마디수가 그대로 남으면 연주 중 페이지가 밀리므로
// 되돌리기가 사용자에게 마지막 안전장치임.

import 'package:baton/cloud/api_client.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/score/ai_analysis.dart';
import 'package:baton/score/score_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
