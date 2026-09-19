// 앱 설정 저장. 지연 보정처럼 기기마다 다른 값과 구매 상태 캐시를 담음.
// 값은 문자열로만 두고 형 변환은 읽는 쪽에서 함. 설정 하나 늘 때마다 스키마를 바꾸지 않으려는 선택.

import 'database.dart';

class SettingsRepo {
  SettingsRepo(this.db);

  final BatonDatabase db;

  /// 없으면 null.
  Future<String?> get(String key) async {
    final row = await (db.select(db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 값을 덮어씀.
  Future<void> set(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  /// 값을 지움. 빈 문자열로 덮으면 "값이 있음"으로 남으므로 행 자체를 없앰.
  Future<void> remove(String key) => (db.delete(db.settings)..where((s) => s.key.equals(key))).go();

  /// 숫자로 읽음. 값이 없거나 깨졌으면 fallback.
  Future<double> getDouble(String key, double fallback) async =>
      double.tryParse(await get(key) ?? '') ?? fallback;

  /// 참·거짓으로 읽음.
  Future<bool> getBool(String key, {bool fallback = false}) async => (await get(key)) == '1'
      ? true
      : (await get(key)) == '0'
      ? false
      : fallback;

  /// 참·거짓을 저장함.
  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');
}

/// 출력 지연 보정(ms). 블루투스 이어폰은 소리가 늦게 나므로 그만큼 클릭을 앞당김.
const kLatencyMsKey = 'latency_ms';

/// 이 기기에만 맞는 설정. 백업을 되살려도 백업 쪽 값 대신 이 기기 값을 그대로 둠.
/// 출력 지연은 이어폰·스피커 조합마다 달라 다른 기기 값을 쓰면 클릭이 어긋나거나 빠짐.
/// 구매 캐시는 이 기기 스토어 계정의 것이라, 남이 만든 백업으로 들어오면 구매 없이 풀림.
const kDeviceLocalKeys = {kLatencyMsKey, kMetronomeUnlockedKey};

/// 메트로놈 구매 여부 캐시. 스토어 확인 전에 화면을 그리기 위한 것이며 진실은 스토어에 있음.
const kMetronomeUnlockedKey = 'metronome_unlocked';
