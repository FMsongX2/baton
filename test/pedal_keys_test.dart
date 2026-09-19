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

  test('기본 넘김 키는 모두 한국어 이름으로 보이고 스페이스도 빈칸이 아님', () {
    expect(pedalKeyLabel(LogicalKeyboardKey.space), '스페이스');
    expect(pedalKeyLabel(LogicalKeyboardKey.arrowRight), '오른쪽 화살표');
    for (final k in [...kDefaultNextKeys, ...kDefaultPrevKeys]) {
      expect(pedalKeyLabel(k).trim(), isNotEmpty);
    }
  });

  test('표에 없는 키는 키보드 표기를 씀', () {
    expect(pedalKeyLabel(LogicalKeyboardKey.keyA), 'A');
    expect(pedalKeyLabel(LogicalKeyboardKey.f13), 'F13');
  });

  test('표기가 공백이거나 없는 키는 키 코드로 보임', () {
    // U+3000은 표기가 전각 공백 한 칸, 0x1100000042는 표기가 아예 없는 키
    expect(pedalKeyLabel(const LogicalKeyboardKey(0x3000)), '키 0x3000');
    expect(pedalKeyLabel(const LogicalKeyboardKey(0x1100000042)), '키 0x1100000042');
  });
}
