// 임포트 입구. PDF·이미지·스캔 결과를 전부 정규화 PDF 한 개로 만들어 라이브러리에 넣음.
// 임시 자리에 다 쓰고 열리는지 확인한 뒤에 DB 행을 만들어, 쓰다 죽어도 파일 없는 악보가 남지 않음.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/db/database.dart';
import '../../core/storage/paths.dart';
import '../score_repo.dart';
import '../thumbnail.dart';
import 'image_to_pdf.dart';

/// 노드 이름 최대 길이. core/db/tables.dart의 Nodes.name 길이 검사와 같게 둠.
const kMaxNodeNameLength = 200;

/// 가져오는 중인 파일을 두는 자리(상대경로). scores/ 밖이라 백업 zip에 섞이지 않음.
const _stagingDir = 'import-staging';

class ImportService {
  /// countPages는 기본으로 pdfium을 씀.
  ImportService(this.db, this.repo, {this.countPages = pdfPageCount});

  final BatonDatabase db;
  final ScoreRepo repo;

  /// PDF 쪽수를 읽는 함수. 테스트가 pdfium 없이 돌 수 있게 바꿔 끼움.
  final Future<int> Function(String path) countPages;

  /// 이 프로세스에서 돌고 있는 가져오기의 임시 디렉토리. 이 밖의 것은 앞선 실행이 끊기며 남긴 조각.
  static final _activeStaging = <String>{};
  static var _stagingSeq = 0;

  /// PDF 파일을 들임. 원본을 악보 디렉토리로 복사함. 만들어진 노드 id를 돌려줌.
  Future<int> importPdf(File src, {String? name, int? parentId}) => _place(
    name: name ?? p.basenameWithoutExtension(src.path),
    parentId: parentId,
    write: (dest) => src.copy(dest.path),
  );

  /// 이미지들을 한 악보로 묶어 들임. 순서가 곧 페이지 순서.
  /// 디코드·PDF 조립은 백그라운드 isolate에서 쪽 단위로 함.
  Future<int> importImages(List<File> images, {required String name, int? parentId}) async {
    final pdf = await imageFilesToPdf([for (final f in images) f.path]);
    return _place(name: name, parentId: parentId, write: (dest) => dest.writeAsBytes(pdf));
  }

  /// 파일을 임시 자리에 쓰고 쪽수를 읽은 뒤 노드를 만들고 파일을 제자리로 옮김.
  /// 어느 단계에서 실패해도 행·디렉토리·임시 파일을 되돌리고 원래 오류를 던짐.
  /// 임시 자리는 가져오기마다 따로 둠. 다른 폴더 화면이나 복구 가져오기가 동시에 돌 수 있음.
  Future<int> _place({
    required String name,
    required int? parentId,
    required Future<void> Function(File dest) write,
  }) async {
    final root = Directory(AppPaths.abs(_stagingDir));
    // 만들기 전에 등록해야 동시에 시작한 가져오기의 정리가 이 자리를 지우지 않음
    final staging = Directory(p.join(root.path, '$pid-${_stagingSeq++}'));
    _activeStaging.add(staging.path);
    final staged = File(p.join(staging.path, 'source.pdf'));
    try {
      await _sweepStaging(root);
      await staging.create(recursive: true);
      await write(staged);
      final count = await countPages(staged.path);
      final id = await repo.createScore(
        name: clampNodeName(name),
        pageCount: count,
        parentId: parentId,
      );
      final dest = File(AppPaths.abs(AppPaths.sourcePdf(id)));
      try {
        await AppPaths.ensureScoreDir(id);
        // 같은 볼륨 안의 원자적 rename. 반쯤 쓰인 source.pdf가 생기지 않음
        await staged.rename(dest.path);
      } catch (_) {
        await _discardScore(id);
        rethrow;
      }
      await generateThumbnail(dest.path, AppPaths.abs(AppPaths.thumbnail(id)));
      return id;
    } finally {
      _activeStaging.remove(staging.path);
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // 남아도 다음 가져오기가 비움
      }
    }
  }

  /// 앞선 실행이 가져오다 끊기며 남긴 임시 디렉토리를 지움. 지금 돌고 있는 가져오기의 것은 둠.
  static Future<void> _sweepStaging(Directory root) async {
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (_activeStaging.contains(e.path)) continue;
      try {
        await e.delete(recursive: true);
      } catch (_) {
        // 다음 가져오기가 다시 지움
      }
    }
  }

  /// 만든 악보 행과 디렉토리를 되돌림. 정리 실패가 원래 오류를 가리지 않게 단계마다 삼킴.
  Future<void> _discardScore(int id) async {
    try {
      await repo.deleteScore(id);
    } catch (_) {
      // 행이 남으면 목록에 보이므로 사용자가 지울 수 있음. 원래 오류를 알리는 편이 먼저
    }
    try {
      await Directory(AppPaths.abs(AppPaths.scoreDir(id))).delete(recursive: true);
    } catch (_) {
      // 디렉토리가 아직 없었을 수 있음
    }
  }
}

/// 악보 이름을 저장 가능한 모양으로 맞춤. 앞뒤 공백을 떼고 길이 상한에서 자르며,
/// 비면 기본 이름을 씀. 긴 파일명 하나 때문에 가져오기 전체가 실패하지 않게 함.
String clampNodeName(String name, {String fallback = '새 악보'}) {
  var s = name.trim();
  if (s.length > kMaxNodeNameLength) {
    s = s.substring(0, kMaxNodeNameLength);
    // 서로게이트 쌍 가운데서 자르면 깨진 글자가 남음
    final last = s.codeUnitAt(s.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) s = s.substring(0, s.length - 1);
    s = s.trimRight();
  }
  return s.isEmpty ? fallback : s;
}

/// PDF의 페이지 수를 읽음. 열지 못하면 던짐.
Future<int> pdfPageCount(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    return doc.pages.length;
  } finally {
    doc.dispose();
  }
}
