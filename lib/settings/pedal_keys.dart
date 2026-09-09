// 페달·키보드 넘김 키 매핑. BLE 페달은 HID 키보드로 들어오므로 어떤 키를 보내는지는 기기마다 다름.
// 기본값으로 시판 페달 대부분을 덮고, 맞지 않는 기기는 학습 모드로 직접 지정함.

import 'package:flutter/services.dart';

import '../core/db/settings_repo.dart';

/// 저장 키. 값은 LogicalKeyboardKey.keyId를 쉼표로 이은 문자열.
const kPedalNextKey = 'pedal_next_keys';
const kPedalPrevKey = 'pedal_prev_keys';

/// 다음 페이지 기본 키. 시판 BLE 페달이 보내는 코드들.
final kDefaultNextKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.space,
};

/// 이전 페이지 기본 키.
final kDefaultPrevKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.pageUp,
};

/// 넘김 키 두 벌. 한쪽에 지정한 키는 다른 쪽에서 빠져 같은 키가 양방향이 되지 않게 함.
class PedalKeys {
  const PedalKeys(this.next, this.prev);

  final Set<LogicalKeyboardKey> next;
  final Set<LogicalKeyboardKey> prev;

  static PedalKeys get defaults => PedalKeys({...kDefaultNextKeys}, {...kDefaultPrevKeys});

  /// 방향을 판정함. 어느 쪽도 아니면 0.
  int directionOf(LogicalKeyboardKey key) {
    if (next.contains(key)) return 1;
    if (prev.contains(key)) return -1;
    return 0;
  }

  /// 키를 한쪽에 넣고 반대쪽에서는 뺌.
  PedalKeys assign(LogicalKeyboardKey key, {required bool forward}) {
    final n = {...next}..remove(key);
    final p = {...prev}..remove(key);
    (forward ? n : p).add(key);
    return PedalKeys(n, p);
  }

  /// 키를 양쪽에서 지움.
  PedalKeys remove(LogicalKeyboardKey key) =>
      PedalKeys({...next}..remove(key), {...prev}..remove(key));
}

/// 저장된 매핑을 읽음. 값이 없거나 깨졌으면 기본값.
Future<PedalKeys> loadPedalKeys(SettingsRepo settings) async {
  final next = _decode(await settings.get(kPedalNextKey));
  final prev = _decode(await settings.get(kPedalPrevKey));
  if (next == null && prev == null) return PedalKeys.defaults;
  return PedalKeys(next ?? {}, prev ?? {});
}

/// 매핑을 저장함. 빈 쪽도 저장해 "기본값으로 되돌아감"과 구분함.
Future<void> savePedalKeys(SettingsRepo settings, PedalKeys keys) async {
  await settings.set(kPedalNextKey, _encode(keys.next));
  await settings.set(kPedalPrevKey, _encode(keys.prev));
}

/// 저장된 매핑을 지워 기본값으로 되돌림.
Future<void> resetPedalKeys(SettingsRepo settings) async {
  await settings.remove(kPedalNextKey);
  await settings.remove(kPedalPrevKey);
}

String _encode(Set<LogicalKeyboardKey> keys) => keys.map((k) => k.keyId).join(',');

/// 저장 문자열을 키 집합으로. 항목 하나가 깨져도 나머지는 살림.
Set<LogicalKeyboardKey>? _decode(String? raw) {
  if (raw == null) return null;
  final out = <LogicalKeyboardKey>{};
  for (final part in raw.split(',')) {
    final id = int.tryParse(part.trim());
    if (id != null) out.add(LogicalKeyboardKey(id));
  }
  return out;
}
