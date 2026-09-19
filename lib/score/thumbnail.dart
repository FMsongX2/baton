// 라이브러리 목록용 첫 페이지 썸네일. 악보는 이름보다 생김새로 알아보는 편이라
// 목록에서 표지를 보여 주는 편이 탐색이 빠름. 만든 결과는 파일로 캐시함.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'page_render.dart';

/// 임시 파일 이름을 가르는 번호. 같은 표지를 동시에 만드는 호출끼리 임시 파일이 겹치지 않게 함.
var _tempSeq = 0;

/// PDF 첫 페이지를 PNG로 렌더해 outPath에 씀. 실패하면 조용히 넘어감.
/// 목록 표시용이라 실패해도 앱 흐름을 막지 않아야 함.
/// 목록 칸과 가져오기가 같은 표지를 동시에 만들고 읽을 수 있어, 옆에 다 쓴 뒤 이름을 바꿔 한 번에 바꿈.
Future<bool> generateThumbnail(String pdfPath, String outPath) async {
  try {
    final bytes = await renderPagePng(pdfPath, 0, kThumbWidth);
    if (bytes == null) return false;
    final out = File(outPath);
    await out.parent.create(recursive: true);
    final temp = File('$outPath.${_tempSeq++}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(outPath);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return true;
  } catch (e) {
    debugPrint('썸네일 저장 실패: $e');
    return false;
  }
}
