// 이 기기의 서버 신원. 코인 소유권 그 자체라 악보·필기와 수명이 다름.
// 백업 zip에는 baton.sqlite와 scores/만 들어가므로, 이 파일에 두면 백업을 남에게 넘겨도
// 코인까지 넘어가지 않음. 앱 DB에 두면 백업을 공유하는 순간 잔액을 함께 넘기게 됨.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/storage/paths.dart';

/// 저장 파일(상대경로). 백업 대상 밖에 있어야 하므로 scores/ 아래에 두지 않음.
const _fileRel = 'device.json';

class DeviceCredentials {
  const DeviceCredentials({required this.token, required this.userId});

  final String token;
  final String userId;
}

/// 저장된 신원을 읽음. 없거나 깨졌으면 null.
Future<DeviceCredentials?> loadDeviceCredentials() async {
  try {
    final file = File(AppPaths.abs(_fileRel));
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return null;
    final token = raw['token'];
    final userId = raw['userId'];
    if (token is! String || userId is! String || token.isEmpty) return null;
    return DeviceCredentials(token: token, userId: userId);
  } catch (e) {
    debugPrint('기기 신원을 읽지 못함: $e');
    return null;
  }
}

/// 신원을 저장함. 실패하면 다음 실행에서 새 기기로 등록되므로 조용히 넘기지 않고 던짐.
Future<void> saveDeviceCredentials(DeviceCredentials value) async {
  final file = File(AppPaths.abs(_fileRel));
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({'token': value.token, 'userId': value.userId}), flush: true);
}

/// 무효가 된 신원을 지움.
Future<void> clearDeviceCredentials() async {
  final file = File(AppPaths.abs(_fileRel));
  if (await file.exists()) await file.delete();
}
