// 필기 도구줄. 연주 중에도 누를 수 있어야 해서 아이콘을 크게 잡고 한 줄에 담음.

import 'package:flutter/material.dart';

import '../theme.dart';

enum ReaderTool { pen, highlighter, eraser }

/// 펜 색 후보. 악보 위에서 서로 구분되고 인쇄 악보의 검정과도 충돌하지 않는 값들.
const kPenColors = <int>[0xFF1A1A1A, 0xFFD32F2F, 0xFF1976D2, 0xFF2E7D32];

/// 굵기 후보. 페이지 폭 대비 비율.
const kPenWidths = <double>[0.0015, 0.003, 0.006];

class DrawToolbar extends StatelessWidget {
  const DrawToolbar({
    super.key,
    required this.tool,
    required this.color,
    required this.width,
    required this.stylusOnly,
    required this.canUndo,
    required this.canRedo,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
    required this.onStylusOnly,
    required this.onUndo,
    required this.onRedo,
  });

  final ReaderTool tool;
  final int color;
  final double width;
  final bool stylusOnly;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<ReaderTool> onTool;
  final ValueChanged<int> onColor;
  final ValueChanged<double> onWidth;
  final VoidCallback onStylusOnly;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// 도구·색·굵기는 가로로 밀어 보고, 실행취소·다시 실행은 오른쪽에 고정해 그림.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      // 실행취소·다시 실행은 스크롤 밖 오른쪽에 고정함. 한 줄에 다 넣으면 폰 세로에서 화면 밖으로 밀려
      // 밀 수 있다는 단서도 없이 숨어 버림
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: kGapS),
              child: Row(
                children: [
                  for (final t in ReaderTool.values)
                    IconButton(
                      tooltip: switch (t) {
                        ReaderTool.pen => '펜',
                        ReaderTool.highlighter => '형광펜',
                        ReaderTool.eraser => '지우개',
                      },
                      isSelected: tool == t,
                      icon: Icon(switch (t) {
                        ReaderTool.pen => Icons.edit_outlined,
                        ReaderTool.highlighter => Icons.brush_outlined,
                        ReaderTool.eraser => Icons.cleaning_services_outlined,
                      }),
                      onPressed: () => onTool(t),
                    ),
                  const _Sep(),
                  for (final c in kPenColors)
                    _ColorDot(color: c, selected: color == c, onTap: () => onColor(c)),
                  const _Sep(),
                  for (final w in kPenWidths)
                    IconButton(
                      // 도형만 있어 스크린리더가 구분하지 못함
                      tooltip: _widthLabel(w),
                      isSelected: width == w,
                      icon: Container(
                        width: 6 + w * 2400,
                        height: 6 + w * 2400,
                        decoration: BoxDecoration(color: scheme.onSurface, shape: BoxShape.circle),
                      ),
                      onPressed: () => onWidth(w),
                    ),
                  const _Sep(),
                  IconButton(
                    tooltip: '스타일러스만 받기',
                    isSelected: stylusOnly,
                    icon: const Icon(Icons.back_hand_outlined),
                    onPressed: onStylusOnly,
                  ),
                ],
              ),
            ),
          ),
          const _Sep(),
          IconButton(
            tooltip: '실행취소',
            icon: const Icon(Icons.undo),
            onPressed: canUndo ? onUndo : null,
          ),
          IconButton(
            tooltip: '다시 실행',
            icon: const Icon(Icons.redo),
            onPressed: canRedo ? onRedo : null,
          ),
          const SizedBox(width: kGapS),
        ],
      ),
    );
  }
}

/// 굵기 이름. 화면에는 도형만 보이므로 라벨은 여기서 붙임.
String _widthLabel(double w) {
  final i = kPenWidths.indexOf(w);
  return switch (i) {
    0 => '가는 선',
    1 => '보통 선',
    _ => '굵은 선',
  };
}

/// 색 이름. 색만으로 구분되면 색각 이상 사용자와 스크린리더가 고를 수 없음.
String _colorLabel(int c) => switch (c) {
  0xFF1A1A1A => '검정',
  0xFFD32F2F => '빨강',
  0xFF1976D2 => '파랑',
  _ => '초록',
};

/// 색 선택 점. 고른 색은 테두리로 표시함.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGapXs),
      child: Tooltip(
        message: _colorLabel(color),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            // 연주 중에 누르는 버튼이라 최소 타깃 48을 지킴. 보이는 점은 그대로 둠
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Container(
              width: selected ? 26 : 22,
              height: selected ? 26 : 22,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kGapS),
    child: SizedBox(
      height: 24,
      child: VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
