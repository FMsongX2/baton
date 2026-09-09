// 임포트 입구. PDF·이미지·스캔 결과를 전부 정규화 PDF 한 개로 만들어 라이브러리에 넣음.
// 파일을 먼저 놓고 DB 행을 만들면 경로를 모르고, 반대로 하면 실패 시 빈 악보가 남음.
// 그래서 DB 행을 먼저 만들고 파일 배치가 실패하면 그 행을 되돌림.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/db/database.dart';
import '../../core/storage/paths.dart';
import '../score_repo.dart';
import '../thumbnail.dart';
import 'image_to_pdf.dart';

class ImportService {
  ImportService(this.db, this.repo);

  final BatonDatabase db;
  final ScoreRepo repo;

  /// PDF 파일을 들임. 원본을 악보 디렉토리로 복사함. 만들어진 노드 id를 돌려줌.
  Future<int> importPdf(File src, {String? name, int? parentId}) => _place(
    name: name ?? _baseName(src.path),
    parentId: parentId,
    write: (dest) => src.copy(dest.path),
  );

  /// 이미지들을 한 악보로 묶어 들임. 순서가 곧 페이지 순서.
  Future<int> importImages(List<File> images, {required String name, int? parentId}) async {
    final bytes = <Uint8List>[];
    for (final f in images) {
      bytes.add(await f.readAsBytes());
    }
    final pdf = await imagesToPdf(bytes);
    return _place(name: name, parentId: parentId, write: (dest) => dest.writeAsBytes(pdf));
  }

  /// 노드를 먼저 만들고 파일을 배치한 뒤 페이지 수를 실제 PDF에서 읽어 채움.
  /// 어느 단계에서 실패해도 반쯤 만들어진 악보가 남지 않게 되돌림.
  Future<int> _place({
    required String name,
    required int? parentId,
    required Future<void> Function(File dest) write,
  }) async {
    // 페이지 수는 파일을 놓아야 알 수 있으므로 1로 시작하고 뒤에서 맞춤
    final id = await repo.createScore(name: name, pageCount: 1, parentId: parentId);
    final dir = await AppPaths.ensureScoreDir(id);
    final dest = File(AppPaths.abs(AppPaths.sourcePdf(id)));
    try {
      await write(dest);
      final count = await pdfPageCount(dest.path);
      await repo.setPageCount(id, count);
      await generateThumbnail(dest.path, AppPaths.abs(AppPaths.thumbnail(id)));
      return id;
    } catch (_) {
      await repo.deleteScore(id);
      await dir.delete(recursive: true).catchError((_) => dir);
      rethrow;
    }
  }

  /// 확장자를 뗀 파일 이름. 악보 이름의 기본값으로 씀.
  String _baseName(String path) => p.basenameWithoutExtension(path);
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
