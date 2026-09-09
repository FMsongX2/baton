// pdfrx 페이지 배치. 표시 순서와 숨김을 여기서 처리해 PDF 자체는 건드리지 않음.
// 필기는 물리 페이지에 묶여 있어 순서를 바꿔도 그대로 따라옴.

import 'dart:math' as math;
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

/// 표시 순서와 한 줄에 놓을 장 수를 반영한 배치 함수를 만듦.
/// order에 없는 페이지는 문서 영역 밖으로 밀어 스크롤로도 닿지 않게 함.
PdfPageLayout Function(List<PdfPage>, PdfViewerParams) makePageLayout({
  required List<int> order,
  required bool twoUp,
}) {
  return (pages, params) {
    final m = params.margin;
    final visible = [
      for (final i in order)
        if (i >= 0 && i < pages.length) i,
    ];
    final shown = visible.isEmpty ? List<int>.generate(pages.length, (i) => i) : visible;

    final maxWidth = pages.fold(0.0, (w, p) => math.max(w, p.width));
    final columns = twoUp ? 2 : 1;
    final width = maxWidth * columns + m * (columns + 1);

    final rects = List<Rect?>.filled(pages.length, null);
    var y = m;
    for (var i = 0; i < shown.length; i += columns) {
      var rowHeight = 0.0;
      for (var c = 0; c < columns && i + c < shown.length; c++) {
        final page = pages[shown[i + c]];
        final x = m + c * (maxWidth + m) + (maxWidth - page.width) / 2;
        rects[shown[i + c]] = Rect.fromLTWH(x, y, page.width, page.height);
        rowHeight = math.max(rowHeight, page.height);
      }
      y += rowHeight + m;
    }

    // 숨긴 페이지는 문서 아래쪽 바깥에 쌓아 둠. documentSize가 y까지라 화면에 오지 않음
    var hiddenY = y + m;
    for (var i = 0; i < pages.length; i++) {
      if (rects[i] != null) continue;
      rects[i] = Rect.fromLTWH(0, hiddenY, pages[i].width, pages[i].height);
      hiddenY += pages[i].height + m;
    }

    return PdfPageLayout(pageLayouts: [for (final r in rects) r!], documentSize: Size(width, y));
  };
}
