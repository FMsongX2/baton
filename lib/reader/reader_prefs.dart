// 리더 화면의 표시·필기·잠금 설정. 곡이 아니라 사람과 장소의 속성이라 악보에 묶지 않고 전역에 둠.
// 무대 반전을 곡마다 다시 켜야 하면 자동 넘김을 쓰는 의미가 없어짐.

import '../core/db/settings_repo.dart';
import 'draw_toolbar.dart';

const kReaderInvertKey = 'reader_invert';
const kReaderTwoUpKey = 'reader_two_up';
const kReaderClickKey = 'reader_click';
const kReaderStylusOnlyKey = 'reader_stylus_only';
const kReaderToolKey = 'reader_tool';
const kReaderColorKey = 'reader_color';
const kReaderWidthKey = 'reader_width';
const kReaderLockKey = 'reader_lock';

/// 처음 열었을 때의 펜 색·굵기. kPenColors·kPenWidths의 첫 값과 같음.
const kDefaultPenColor = 0xFF1A1A1A;
const kDefaultPenWidth = 0.003;

/// 리더가 열릴 때 복원하는 값 묶음.
class ReaderPrefs {
  /// 저장값이 없을 때의 기본값으로 채움. twoUp은 null이라 화면 비율에 맡김.
  const ReaderPrefs({
    this.invert = false,
    this.twoUp,
    this.clickOn = true,
    this.stylusOnly = false,
    this.tool = ReaderTool.pen,
    this.color = kDefaultPenColor,
    this.width = kDefaultPenWidth,
    this.locked = false,
  });

  final bool invert;

  /// null이면 화면 비율에 맡김. 한 번 정하면 회전해도 유지됨.
  final bool? twoUp;

  final bool clickOn;
  final bool stylusOnly;
  final ReaderTool tool;
  final int color;
  final double width;

  /// 터치 잠금. 세트리스트를 따라 곡을 바꿀 때마다 다시 켜지 않도록 곡이 아니라 여기에 둠.
  final bool locked;
}

/// 저장된 값을 읽음. 없으면 기본값.
Future<ReaderPrefs> loadReaderPrefs(SettingsRepo settings) async {
  final twoUp = await settings.get(kReaderTwoUpKey);
  final tool = int.tryParse(await settings.get(kReaderToolKey) ?? '');
  final color = int.tryParse(await settings.get(kReaderColorKey) ?? '');
  return ReaderPrefs(
    invert: await settings.getBool(kReaderInvertKey),
    // 저장한 적 없음과 두 장씩 끔을 구분해야 함. 앞은 자동, 뒤는 사용자가 정한 값
    twoUp: twoUp == null ? null : twoUp == '1',
    clickOn: await settings.getBool(kReaderClickKey, fallback: true),
    stylusOnly: await settings.getBool(kReaderStylusOnlyKey),
    tool: tool != null && tool >= 0 && tool < ReaderTool.values.length
        ? ReaderTool.values[tool]
        : ReaderTool.pen,
    color: color ?? kDefaultPenColor,
    width: await settings.getDouble(kReaderWidthKey, kDefaultPenWidth),
    locked: await settings.getBool(kReaderLockKey),
  );
}
