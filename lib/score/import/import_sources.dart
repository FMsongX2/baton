// 가져오기 원천(파일 선택기·사진 선택기·문서 스캐너)의 앞뒤 처리. 오류를 행동이 담긴 문구로 바꾸고,
// 원천이 남긴 사본을 지우고, Android에서 Activity가 죽는 사이 끝난 선택을 되찾음. 화면 흐름은 호출자 몫.

import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'image_to_pdf.dart';

/// 가져온 파일이 어디서 왔는지. 뒷정리 방법이 원천마다 다름.
enum ImportSource { files, images, scan }

/// Activity가 죽는 사이 끝나 Dart로 돌아오지 못한 가져오기.
class LostImport {
  /// paths는 이미 쪽 순서로 세운 것을 받음.
  const LostImport(this.source, this.paths);

  final ImportSource source;
  final List<String> paths;
}

/// 문서 스캐너를 띄움. iOS 기본값인 PNG는 쪽마다 원시 비트맵으로 풀려 메모리가 쌓이므로 JPEG로 받음.
/// 취소하면 null. 권한 거부·기기 미지원은 CunningDocumentScannerException으로 던짐.
Future<List<String>?> scanPages() => CunningDocumentScanner.getPictures(
  iosScannerOptions: IosScannerOptions(
    imageFormat: IosImageFormat.jpg,
    jpgCompressionQuality: kImportJpegQuality / 100,
  ),
);

/// 가져오기에서 난 오류를 사용자가 할 수 있는 행동이 담긴 한국어 문구로 바꿈.
/// 원문 예외는 영어이고 원인만 말하므로 그대로 보여 주지 않음.
String importErrorMessage(Object e) {
  if (e is CunningDocumentScannerException) {
    return switch (e.code) {
      'permission_denied' => '카메라 권한이 꺼져 있음. 설정 > Baton에서 카메라를 허용한 뒤 다시 스캔',
      'UNAVAILABLE' => '이 기기는 문서 스캐너를 쓸 수 없음. 사진으로 찍어 이미지 가져오기로 넣을 수 있음',
      // ERROR는 스캐너 시작 실패·ML Kit 오류·저장 실패를 함께 씀. 원인을 하나로 단정하지 않음
      _ => '스캔을 마치지 못함. 저장공간을 확인하고 다시 스캔. 계속 안 되면 사진으로 찍어 이미지 가져오기로 넣음',
    };
  }
  if (e is PlatformException) {
    return switch (e.code) {
      'photo_access_denied' ||
      'photo_access_restricted' => '사진 접근 권한이 꺼져 있음. 설정 > Baton > 사진에서 허용한 뒤 다시 고름',
      'missing_valid_image_uri' ||
      'no_valid_image_uri' ||
      'invalid_image' => '고른 사진을 읽지 못함. 클라우드에만 있는 사진이면 기기에 내려받은 뒤 다시 고름',
      _ => '파일을 고르지 못함. 잠시 뒤 다시 시도',
    };
  }
  if (e is PdfPasswordException) return '암호가 걸린 PDF라 열 수 없음. 암호를 푼 파일로 다시 가져와야 함';
  if (e is PdfException) return '손상됐거나 PDF가 아닌 파일이라 열 수 없음. 다른 앱에서 열리는지 확인';
  if (e is FormatException) return '${e.message}. JPG나 PNG로 저장해 다시 가져와야 함';
  // ENOSPC. Android(Linux)와 iOS(Darwin) 모두 28
  if (e is FileSystemException && e.osError?.errorCode == 28) {
    return '저장공간이 부족함. 공간을 비운 뒤 다시 시도';
  }
  return '가져오지 못함. 다시 해도 같으면 파일이 다른 앱에서 열리는지 확인';
}

/// 가져오기가 끝난 뒤(성공·실패·취소 모두) 원천이 남긴 사본을 지움. 원본 사진·파일은 건드리지 않음.
/// 스캔은 paths와 무관하게 플러그인 저장소를 통째로 비움. 앞 실행이 남긴 쪽도 함께 지워짐.
/// Android에서는 캐시가 아닌 외부 파일 디렉토리라 OS가 치우지 않음.
Future<void> discardImportSources(ImportSource source, Iterable<String> paths) async {
  try {
    if (source == ImportSource.scan) {
      await CunningDocumentScanner.cleanCache();
    } else {
      await deleteTempCopies(paths);
    }
  } catch (e) {
    debugPrint('가져오기 사본 정리 실패: $e');
  }
}

/// 앱 임시·캐시 디렉토리 안의 경로만 지우고, 선택기가 사본마다 만든 상위 디렉토리도 비었으면 지움.
/// 선택기가 원본 경로를 그대로 줬을 수 있어 그 밖은 건드리지 않음. roots는 테스트가 바꿔 끼움.
Future<void> deleteTempCopies(Iterable<String> paths, {List<String>? roots}) async {
  final bases = <String>{
    for (final r
        in roots ??
            [
              // iOS 사진·파일 선택기는 tmp에 사본을 둠
              Directory.systemTemp.path,
              // Android 선택기는 cacheDir에 사본을 둠
              (await getTemporaryDirectory()).path,
            ])
      ?_realPath(r),
  };
  for (final path in paths) {
    final real = _realPath(path);
    if (real == null) continue;
    final base = bases.where((b) => p.isWithin(b, real)).firstOrNull;
    if (base == null) continue;
    try {
      await File(real).delete();
      final parent = p.dirname(real);
      // 비어 있지 않으면 실패하고 남음. 다른 사본이 든 디렉토리를 지우지 않음
      if (parent != base) await Directory(parent).delete();
    } catch (_) {
      // 이미 지워졌거나 다른 사본이 남아 있음
    }
  }
}

/// 심볼릭 링크를 푼 절대경로. iOS는 /var와 /private/var가 섞여 오므로 비교 전에 맞춤. 없으면 null.
String? _realPath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } catch (_) {
    return null;
  }
}

/// 유실 가져오기를 찾는 함수의 주입 지점. 테스트가 Android 없이 복구 흐름을 띄울 때 바꿔 끼움.
final findLostImportProvider = Provider<Future<LostImport?> Function()>((ref) => findLostImport);

/// 잃어버린 스캔이나 사진 선택을 찾음. Android만 해당하고 없거나 읽지 못하면 null.
/// 사진 선택기는 결과를 백그라운드에서 복사하므로 앱이 막 떴을 때는 아직 없을 수 있어 한 번 더 봄.
/// ponytail: 3초 뒤 한 번만 다시 봄. 복사가 더 오래 걸리면 놓침. 자주 놓치면 resumed마다 확인.
Future<LostImport?> findLostImport() async {
  if (!Platform.isAndroid) return null;
  try {
    final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
    final dir = dirs == null || dirs.isEmpty ? null : dirs.first;
    if (dir != null && await dir.exists()) {
      final scans = orderLostScanFiles([await for (final e in dir.list()) e.path]);
      if (scans.isNotEmpty) return LostImport(ImportSource.scan, scans);
    }
    for (final wait in const [Duration.zero, Duration(seconds: 3)]) {
      await Future<void>.delayed(wait);
      final lost = await ImagePicker().retrieveLostData();
      final files = lost.files ?? [?lost.file];
      if (files.isNotEmpty) {
        return LostImport(ImportSource.images, orderByModified([for (final f in files) f.path]));
      }
    }
  } catch (e) {
    debugPrint('잃어버린 가져오기 확인 실패: $e');
  }
  return null;
}

/// 스캐너 플러그인이 옮겨 놓고도 결과를 전하지 못한 쪽 이미지를 골라 순서대로 세움.
/// 이름은 `DOCUMENT_SCAN_<쪽>_<yyyyMMdd_HHmmss><난수>.jpg`. 쪽을 차례로 옮기므로 시각, 쪽 번호 순.
List<String> orderLostScanFiles(Iterable<String> paths) {
  final pages = <({String path, String stamp, int page})>[];
  for (final path in paths) {
    final m = _scanFileName.firstMatch(p.basename(path));
    if (m != null) pages.add((path: path, stamp: m[2]!, page: int.parse(m[1]!)));
  }
  pages.sort((a, b) {
    final byTime = a.stamp.compareTo(b.stamp);
    return byTime != 0 ? byTime : a.page.compareTo(b.page);
  });
  return [for (final x in pages) x.path];
}

final _scanFileName = RegExp(r'^DOCUMENT_SCAN_(\d+)_(\d{8}_\d{6})\d*\.jpg$');

/// 파일을 수정 시각 순으로 세움. image_picker는 되찾은 경로를 집합으로 저장해 고른 순서를 잃지만,
/// 사본을 고른 순서대로 하나씩 만들므로 수정 시각이 그 순서를 담음. 없는 파일은 뺌.
List<String> orderByModified(Iterable<String> paths) {
  final files = [
    for (final path in paths)
      if (File(path).existsSync()) (path: path, at: File(path).lastModifiedSync()),
  ];
  files.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.path.compareTo(b.path);
  });
  return [for (final f in files) f.path];
}
