// 문서 좌표와 페이지 정규 좌표 사이의 변환.
// pdfrx가 pagePaintCallbacks로 주는 pageRect는 확대·이동을 적용하기 전 문서 좌표계이므로
// 포인터 위치도 PdfViewerController.globalToDocument로 같은 계로 옮긴 뒤에 다뤄야 함.

import 'dart:ui';

/// 점이 어느 페이지 위인지 찾음. 어느 페이지에도 없으면 null.
/// 페이지가 겹쳐 놓이는 배치에서는 인덱스가 작은 쪽을 먼저 잡음.
int? pageAt(Map<int, Rect> pageRects, Offset p) {
  final keys = pageRects.keys.toList()..sort();
  for (final k in keys) {
    if (pageRects[k]!.contains(p)) return k;
  }
  return null;
}

/// 문서 좌표를 페이지 정규 좌표(0~1)로 바꿈.
/// 페이지를 벗어난 점은 가장자리로 붙임. 손이 페이지 밖으로 나가도 획이 끊기지 않게 함.
Offset toNormalized(Offset document, Rect pageRect) {
  if (pageRect.width <= 0 || pageRect.height <= 0) return Offset.zero;
  return Offset(
    ((document.dx - pageRect.left) / pageRect.width).clamp(0.0, 1.0),
    ((document.dy - pageRect.top) / pageRect.height).clamp(0.0, 1.0),
  );
}

/// 페이지 정규 좌표를 문서 좌표로. 필기 위치를 화면 요소와 맞출 때 씀.
Offset toDocument(Offset normalized, Rect pageRect) => Offset(
  pageRect.left + normalized.dx * pageRect.width,
  pageRect.top + normalized.dy * pageRect.height,
);
