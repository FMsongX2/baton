// 앱 파일 경로 규칙. DB에는 상대경로만 저장하고 절대경로는 이 파일에서만 만듦.
// iOS 컨테이너 UUID가 앱 업데이트마다 바뀌므로 절대경로를 저장하면 업데이트 직후 전 악보가 사라짐.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  static Directory? _documents;

  /// 앱 시작 시 한 번 호출함. 이후 abs()가 동작함.
  static Future<void> init() async {
    _documents = await getApplicationDocumentsDirectory();
  }

  /// 테스트에서 임시 디렉토리를 물릴 때 씀.
  static void overrideDocuments(Directory dir) => _documents = dir;

  /// 상대경로를 절대경로로. init 전에 부르면 던짐.
  /// 앱 디렉토리를 벗어나는 경로는 거부함. DB의 fileRel은 백업으로 들어올 수 있어
  /// 신뢰할 수 없고, 그대로 쓰면 남이 만든 백업 하나로 임의 경로를 읽고 쓰게 됨.
  static String abs(String rel) {
    final d = _documents;
    if (d == null) throw StateError('AppPaths.init()을 먼저 호출해야 함');
    final root = p.normalize(d.path);
    final target = p.normalize(p.join(root, rel));
    if (target != root && !p.isWithin(root, target)) {
      throw ArgumentError('앱 디렉토리 밖을 가리키는 경로: $rel');
    }
    return target;
  }

  /// 악보 하나가 쓰는 디렉토리(상대경로).
  static String scoreDir(int nodeId) => p.join('scores', '$nodeId');

  /// 정규화된 PDF 경로(상대경로). 뷰어·주석·내보내기가 전부 이 파일만 봄.
  static String sourcePdf(int nodeId) => p.join(scoreDir(nodeId), 'source.pdf');

  /// 라이브러리 목록에 쓰는 첫 페이지 썸네일(상대경로).
  static String thumbnail(int nodeId) => p.join(scoreDir(nodeId), 'thumb.png');

  /// 악보 디렉토리를 만들고 절대경로를 돌려줌.
  static Future<Directory> ensureScoreDir(int nodeId) =>
      Directory(abs(scoreDir(nodeId))).create(recursive: true);
}
