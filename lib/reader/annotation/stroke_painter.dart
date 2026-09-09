// 획을 페이지 사각형 위에 그림. 정규 좌표를 페이지 픽셀로 옮긴 뒤 외곽선을 만들어 채움.
// pdfrx의 pagePaintCallbacks가 매 프레임 호출되므로 Path를 크기별로 캐시함.

import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import 'stroke.dart';

/// 형광펜 굵기 배수. 펜보다 굵고 평평하게 보이도록 둠.
const _highlighterScale = 3.0;

/// 획 하나의 외곽선 Path를 만듦. 같은 페이지 크기로 다시 부르면 캐시를 돌려줌.
Path strokePath(Stroke s, Size pageSize) {
  final cached = s.cachedPath;
  if (cached != null && s.cachedSize == pageSize) return cached;

  // 정규 좌표를 픽셀로 옮겨서 외곽선을 만듦. perfect_freehand의 두께·평활화 기본값이
  // 픽셀 스케일을 전제하므로 정규 좌표 그대로 넘기면 모양이 깨짐.
  final pv = <PointVector>[];
  for (var i = 0; i < s.points.length; i++) {
    final p = s.points[i];
    pv.add(
      PointVector(
        p.dx * pageSize.width,
        p.dy * pageSize.height,
        s.pressures != null && i < s.pressures!.length ? s.pressures![i] : null,
      ),
    );
  }

  final size =
      s.width * pageSize.width * (s.tool == StrokeTool.highlighter ? _highlighterScale : 1.0);
  final outline = getStroke(
    pv,
    options: StrokeOptions(
      size: size,
      // 형광펜은 필압에 따라 굵기가 변하면 지저분해지므로 균일하게 둠
      thinning: s.tool == StrokeTool.highlighter ? 0.0 : 0.5,
      smoothing: 0.5,
      streamline: 0.5,
      simulatePressure: s.pressures == null,
      isComplete: true,
    ),
  );

  final path = Path();
  if (outline.isNotEmpty) {
    path.moveTo(outline.first.dx, outline.first.dy);
    for (final o in outline.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
  }
  s.cachedPath = path;
  s.cachedSize = pageSize;
  return path;
}

/// 페이지 사각형 안에 획들을 그림. canvas는 뷰어 좌표계라 pageRect만큼 옮겨서 씀.
void paintStrokes(Canvas canvas, Rect pageRect, List<Stroke> strokes) {
  if (strokes.isEmpty) return;
  canvas.save();
  canvas.translate(pageRect.left, pageRect.top);
  final size = pageRect.size;
  for (final s in strokes) {
    final paint = Paint()
      ..color = Color(s.color)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    // 형광펜은 겹친 부분이 검게 쌓이지 않도록 곱 혼합으로 칠함
    if (s.tool == StrokeTool.highlighter) paint.blendMode = BlendMode.multiply;
    canvas.drawPath(strokePath(s, size), paint);
  }
  canvas.restore();
}
