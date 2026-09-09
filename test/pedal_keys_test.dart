// 페달 키 매핑 저장·복원. 한 키가 양방향에 동시에 들어가면 넘김이 제자리를 맴돌므로 그 부분을 고정함.

import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/settings/pedal_keys.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BatonDatabase db;
  late SettingsRepo settings;

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepo(db);
  });

  tearDown(() => db.close());

  test('저장한 적이 없으면 기본 매핑을 씀', () async {
    final keys = await loadPedalKeys(settings);
    expect(keys.directionOf(LogicalKeyboardKey.arrowRight), 1);
    expect(keys.directionOf(LogicalKeyboardKey.arrowLeft), -1);
    expect(keys.directionOf(LogicalKeyboardKey.keyQ), 0);
  });

  test('한 키를 반대 방향에 지정하면 원래 방향에서 빠짐', () {
    final keys = PedalKeys.defaults.assign(LogicalKeyboardKey.arrowRight, forward: false);
    expect(keys.directionOf(LogicalKeyboardKey.arrowRight), -1);
    expect(keys.next.contains(LogicalKeyboardKey.arrowRight), isFalse);
  });

  test('저장하고 다시 읽으면 같은 매핑', () async {
    final keys = PedalKeys.defaults.assign(LogicalKeyboardKey.f13, forward: true);
    await savePedalKeys(settings, keys);

    final loaded = await loadPedalKeys(settings);
    expect(loaded.directionOf(LogicalKeyboardKey.f13), 1);
    expect(loaded.next.length, keys.next.length);
  });

  test('한쪽을 비워 저장해도 기본값으로 되살아나지 않음', () async {
    await savePedalKeys(settings, const PedalKeys({}, {}));
    final loaded = await loadPedalKeys(settings);
    expect(loaded.next, isEmpty);
    expect(loaded.prev, isEmpty);
  });

  test('되돌리면 기본 매핑으로 감', () async {
    await savePedalKeys(settings, const PedalKeys({}, {}));
    await resetPedalKeys(settings);
    final loaded = await loadPedalKeys(settings);
    expect(loaded.directionOf(LogicalKeyboardKey.space), 1);
  });
}
