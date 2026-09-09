// 리더 표시·필기 설정의 저장과 복원. 두 장씩은 "저장한 적 없음"과 "끔"을 구분해야 하므로
// 그 3상태가 왕복하는지를 특히 고정함.

import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/reader/draw_toolbar.dart';
import 'package:baton/reader/reader_prefs.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BatonDatabase db;
  late SettingsRepo settings;

  setUp(() {
    db = BatonDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepo(db);
  });

  tearDown(() => db.close());

  test('저장한 적이 없으면 기본값이고 두 장씩은 자동', () async {
    final p = await loadReaderPrefs(settings);
    expect(p.invert, isFalse);
    expect(p.twoUp, isNull);
    expect(p.clickOn, isTrue);
    expect(p.tool, ReaderTool.pen);
    expect(p.color, kDefaultPenColor);
  });

  test('두 장씩을 끄면 자동과 구분됨', () async {
    await settings.setBool(kReaderTwoUpKey, false);
    expect((await loadReaderPrefs(settings)).twoUp, isFalse);

    await settings.setBool(kReaderTwoUpKey, true);
    expect((await loadReaderPrefs(settings)).twoUp, isTrue);
  });

  test('저장한 값이 그대로 돌아옴', () async {
    await settings.setBool(kReaderInvertKey, true);
    await settings.setBool(kReaderClickKey, false);
    await settings.setBool(kReaderStylusOnlyKey, true);
    await settings.set(kReaderToolKey, '${ReaderTool.highlighter.index}');
    await settings.set(kReaderColorKey, '${0xFFD32F2F}');
    await settings.set(kReaderWidthKey, '0.006');

    final p = await loadReaderPrefs(settings);
    expect(p.invert, isTrue);
    expect(p.clickOn, isFalse);
    expect(p.stylusOnly, isTrue);
    expect(p.tool, ReaderTool.highlighter);
    expect(p.color, 0xFFD32F2F);
    expect(p.width, 0.006);
  });

  test('깨진 값은 기본값으로 떨어지고 던지지 않음', () async {
    await settings.set(kReaderToolKey, '99');
    await settings.set(kReaderColorKey, '색깔');
    await settings.set(kReaderWidthKey, 'x');

    final p = await loadReaderPrefs(settings);
    expect(p.tool, ReaderTool.pen);
    expect(p.color, kDefaultPenColor);
    expect(p.width, kDefaultPenWidth);
  });
}
