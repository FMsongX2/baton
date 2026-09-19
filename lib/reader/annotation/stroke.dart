// 필기 획 모델. 좌표는 페이지 정규 좌표(0~1)로만 저장해 확대·회전·기기 변경에 영향받지 않음.
// 원본 PDF는 건드리지 않고 이 획들을 오버레이로 그림.

import 'dart:ui';

enum StrokeTool { pen, highlighter }

class Stroke {
  Stroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.pressures,
  });

  final StrokeTool tool;

  /// ARGB. 형광펜은 알파를 낮춰 저장함.
  final int color;

  /// 페이지 폭 대비 비율. 확대해도 굵기 비율이 유지됨.
  final double width;

  /// 페이지 정규 좌표(0~1).
  final List<Offset> points;

  /// 스타일러스 필압(0~1). 없으면 렌더러가 시뮬레이션함.
  final List<double>? pressures;

  /// 렌더 캐시. 직렬화 대상이 아니며 pagePaintCallbacks가 매 프레임 호출되는 비용을 막음.
  Path? cachedPath;
  Size? cachedSize;

  /// 저장 형식. 좌표는 [x,y,x,y,...] 평탄 배열로 두어 JSON 크기를 줄임.
  Map<String, dynamic> toJson() => {
    't': tool.index,
    'c': color,
    'w': width,
    'p': [
      for (final o in points) ...[o.dx, o.dy],
    ],
    if (pressures != null) 'r': pressures,
  };

  /// 저장 형식에서 복원함. 좌표 개수가 홀수면 마지막 값을 버림.
  factory Stroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List).cast<num>();
    final pts = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(Offset(flat[i].toDouble(), flat[i + 1].toDouble()));
    }
    return Stroke(
      tool: StrokeTool.values[j['t'] as int],
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      points: pts,
      pressures: (j['r'] as List?)?.cast<num>().map((n) => n.toDouble()).toList(),
    );
  }

  /// 지우개 히트 테스트. 정규 좌표 기준 거리가 tolerance 이하면 true.
  bool hitTest(Offset p, double tolerance) {
    if (points.isEmpty) return false;
    if (points.length == 1) return (points.first - p).distance <= tolerance;
    for (var i = 0; i + 1 < points.length; i++) {
      if (_distanceToSegment(p, points[i], points[i + 1]) <= tolerance) return true;
    }
    return false;
  }
}

/// 점 p와 선분 ab 사이의 최단 거리. 지우개 판정에만 씀.
double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
}
