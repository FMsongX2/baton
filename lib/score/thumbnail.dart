// 라이브러리 목록용 첫 페이지 썸네일. 악보는 이름보다 생김새로 알아보는 편이라
// 목록에서 표지를 보여 주는 편이 탐색이 빠름. 만든 결과는 파일로 캐시함.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'page_render.dart';

/// PDF 첫 페이지를 PNG로 렌더해 outPath에 씀. 실패하면 조용히 넘어감.
/// 목록 표시용이라 실패해도 앱 흐름을 막지 않아야 함.
Future<bool> generateThumbnail(String pdfPath, String outPath) async {
  try {
    final bytes = await renderPagePng(pdfPath, 0, kThumbWidth);
    if (bytes == null) return false;
    final out = File(outPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
    return true;
  } catch (e) {
    debugPrint('썸네일 저장 실패: $e');
    return false;
  }
}
