// 기기 신원 저장. 이 값이 곧 코인 소유권이라 백업에 실리면 백업을 넘기는 순간 잔액도 넘어감.
// 파일이 백업 대상(baton.sqlite, scores/) 밖에 있다는 점을 고정함.

import 'dart:io';

import 'package:baton/cloud/device_credentials.dart';
import 'package:baton/core/storage/paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('baton-cred-test');
    AppPaths.overrideDocuments(docs);
  });

  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  test('저장한 적이 없으면 null', () async {
    expect(await loadDeviceCredentials(), isNull);
  });

  test('저장하고 다시 읽으면 같은 값', () async {
    await saveDeviceCredentials(const DeviceCredentials(token: 'tok', userId: 'uid'));
    final loaded = await loadDeviceCredentials();
    expect(loaded!.token, 'tok');
    expect(loaded.userId, 'uid');
  });

  test('지우면 다시 null', () async {
    await saveDeviceCredentials(const DeviceCredentials(token: 'tok', userId: 'uid'));
    await clearDeviceCredentials();
    expect(await loadDeviceCredentials(), isNull);
  });

  test('깨진 파일은 null로 떨어져 새 기기로 등록되게 함', () async {
    await File(AppPaths.abs('device.json')).writeAsString('{ not json');
    expect(await loadDeviceCredentials(), isNull);
  });

  test('신원 파일은 백업이 담는 두 곳 밖에 있음', () async {
    await saveDeviceCredentials(const DeviceCredentials(token: 'tok', userId: 'uid'));
    final rel = docs
        .listSync()
        .map((e) => e.path.substring(docs.path.length + 1))
        .where((n) => n != '.')
        .toList();
    expect(rel, contains('device.json'));
    // exportBackup은 baton.sqlite와 scores/ 아래만 담음
    expect(rel.any((n) => n == 'baton.sqlite' || n == 'scores'), isFalse);
  });
}
