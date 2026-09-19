// 악보 뷰어 위에 얹는 입력·표시 층. 넘김 탭 판정, 그리기 입력, 무대용 색 반전을 뷰어와 분리해 둠.
// 셋 다 아래 뷰어의 제스처와 상태를 빼앗지 않음(계약).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 어두운 무대용 색 반전. 뷰어와 그리는 중인 획이 같은 필터를 써야 서로 어긋나지 않음.
const kInvertFilter = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// 화면을 1:2:1로 나눠 좌우는 넘김, 가운데는 조작줄 토글로 씀.
/// 제스처 경합에 끼지 않고 포인터만 지켜봄. 그래서 아래 뷰어의 더블탭 판정(300ms)을 기다리지 않고,
/// 빠르게 두 번 치면 두 번 넘김. 움직이거나 두 손가락이 닿으면 탭으로 치지 않아 드래그·핀치는 뷰어가 받음.
class TapZones extends StatefulWidget {
  /// 좌우 넘김과 가운데 토글 콜백을 받음. turns가 false면 화면 전체를 가운데 칸으로 씀.
  const TapZones({super.key, required this.onCenter, required this.onStep, this.turns = true});

  final VoidCallback onCenter;

  /// 좌우 칸을 눌렀을 때. 이전은 -1, 다음은 1.
  final ValueChanged<int> onStep;

  /// false면 좌우 넘김 칸을 없애고 화면 전체를 가운데 칸으로 씀. 터치 잠금에서 씀.
  final bool turns;

  /// 지켜보는 포인터를 들고 있는 상태를 만듦.
  @override
  State<TapZones> createState() => _TapZonesState();
}

/// 탭 후보 포인터 하나와 닿아 있는 포인터 수를 들고 떼는 순간 칸을 판정함.
class _TapZonesState extends State<TapZones> {
  /// 탭 후보로 지켜보는 포인터. 움직이거나 다른 손가락이 닿으면 버림.
  int? _pointer;
  Offset _downAt = Offset.zero;
  Duration _downTime = Duration.zero;

  /// 지금 닿아 있는 포인터 수. 둘 이상이면 핀치라 탭으로 치지 않음.
  int _touching = 0;

  /// 손이 닿음. 이미 다른 손가락이 닿아 있으면 둘 다 탭 후보에서 뺌.
  void _onDown(PointerDownEvent e) {
    _touching++;
    if (_touching > 1) {
      _pointer = null;
      return;
    }
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _downTime = e.timeStamp;
  }

  /// 손이 끌리면 드래그로 보고 탭 후보에서 뺌.
  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _pointer && (e.localPosition - _downAt).distance > kTouchSlop) {
      _pointer = null;
    }
  }

  /// 손을 뗌. 짧게 누른 탭이면 떼는 즉시 그 칸의 동작을 부름.
  /// 손을 댄 채 이 층이 트리에서 빠져도(그리기 전환, 화면 닫기) 떼는 이벤트는 이미 잡힌 경로로 옴.
  /// 그때는 크기도 콜백도 낡았으므로 아무것도 하지 않음.
  void _onUp(PointerUpEvent e) {
    if (!mounted) return;
    _release();
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (e.timeStamp - _downTime > kLongPressTimeout) return;
    final width = context.size?.width ?? 0;
    final x = e.localPosition.dx;
    if (widget.turns && x < width / 4) {
      widget.onStep(-1);
    } else if (widget.turns && x > width * 3 / 4) {
      widget.onStep(1);
    } else {
      widget.onCenter();
    }
  }

  /// 시스템이 포인터를 거둠. 탭으로 치지 않음.
  void _onCancel(PointerCancelEvent e) {
    _release();
    if (e.pointer == _pointer) _pointer = null;
  }

  /// 닿아 있는 포인터 수를 하나 줄임.
  void _release() {
    if (_touching > 0) _touching--;
  }

  /// 칸마다 스크린리더용 버튼만 두고 포인터는 한 곳에서 판정함. 자식은 히트되지 않아 아래 뷰어까지 닿음.
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: Row(
      children: [
        if (widget.turns)
          Expanded(
            child: Semantics(
              button: true,
              label: '이전 페이지',
              onTap: () => widget.onStep(-1),
              child: const SizedBox.expand(),
            ),
          ),
        Expanded(
          flex: 2,
          child: Semantics(
            button: true,
            label: '조작줄',
            onTap: widget.onCenter,
            child: const SizedBox.expand(),
          ),
        ),
        if (widget.turns)
          Expanded(
            child: Semantics(
              button: true,
              label: '다음 페이지',
              onTap: () => widget.onStep(1),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    ),
  );
}

/// 그리기 모드의 입력층. 포인터를 그대로 넘겨 획을 만들게 하고, 그리는 중인 획(child)은 입력을 받지 않음.
/// 스타일러스 전용이면 손가락은 아래 뷰어로 흘려보내 스크롤·확대를 살리고,
/// 펜은 제스처 경합을 먼저 차지해 그리는 동안 뷰어가 끌려가지 않게 함.
class DrawInputLayer extends StatelessWidget {
  /// 포인터 콜백과 그리는 중인 획(child)을 받음. stylusOnly면 손가락을 아래 뷰어로 흘려보냄.
  const DrawInputLayer({
    super.key,
    required this.stylusOnly,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
    required this.child,
  });

  final bool stylusOnly;
  final PointerDownEventListener onDown;
  final PointerMoveEventListener onMove;
  final PointerUpEventListener onUp;
  final PointerCancelEventListener onCancel;
  final Widget child;

  static const _pens = {PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};

  /// 스타일러스 전용이면 펜 포인터를 선점하는 인식기를 둠. 아니면 불투명 층이 모든 입력을 받음.
  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      if (stylusOnly)
        EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(supportedDevices: _pens),
          (_) {},
        ),
    },
    child: Listener(
      behavior: stylusOnly ? HitTestBehavior.translucent : HitTestBehavior.opaque,
      onPointerDown: onDown,
      onPointerMove: onMove,
      onPointerUp: onUp,
      onPointerCancel: onCancel,
      // 그리는 중인 획은 화면 전체를 덮는 CustomPaint라 히트되면 그 아래로 아무 입력도 가지 않음
      child: IgnorePointer(child: child),
    ),
  );
}

/// 포인터 필압을 0~1로 맞춤. 기기마다 범위가 달라(Apple Pencil은 4를 넘음) 그대로 저장하면
/// 같은 굵기 설정이 기기마다 몇 배씩 달라짐. 펜이 아니거나 범위를 모르면 null이라 렌더러가 속도로 흉내 냄.
double? strokePressure(PointerEvent e) {
  if (e.kind != PointerDeviceKind.stylus && e.kind != PointerDeviceKind.invertedStylus) return null;
  final range = e.pressureMax - e.pressureMin;
  if (range <= 0) return null;
  return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
}

/// 켜고 끌 수 있는 색 반전. 켜든 끄든 트리 모양이 같아 아래 뷰어의 상태(보던 쪽·배율)가 유지되고,
/// 꺼져 있으면 합성 레이어를 만들지 않아 평상시에 saveLayer 비용이 없음.
class InvertColors extends SingleChildRenderObjectWidget {
  /// enabled가 켜져 있을 때만 child를 반전해 그림. 켜고 꺼도 child는 다시 만들지 않음.
  const InvertColors({super.key, required this.enabled, super.child});

  final bool enabled;

  /// 반전 여부를 들고 그리는 렌더 객체를 만듦.
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInvertColors(enabled);

  /// 반전 여부만 바꿈. 렌더 객체와 자식은 그대로 둠.
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderInvertColors).enabled = enabled;
  }
}

/// InvertColors의 렌더 객체. 켜져 있을 때만 색 필터 레이어를 들고 있음.
class _RenderInvertColors extends RenderProxyBox {
  /// 처음 반전 여부로 만듦. 이후에는 enabled 설정자로만 바꿈.
  _RenderInvertColors(this._enabled);

  bool _enabled;

  /// 바뀌면 합성 여부와 그림을 다시 정함.
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  /// 켜져 있을 때만 합성 레이어가 필요함. 꺼지면 부모 레이어에 바로 그림.
  @override
  bool get alwaysNeedsCompositing => _enabled && child != null;

  /// 켜져 있을 때만 색 필터 레이어를 씌워 그림. 꺼지면 레이어를 버리고 자식을 그대로 그림.
  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushColorFilter(
      offset,
      kInvertFilter,
      super.paint,
      oldLayer: layer as ColorFilterLayer?,
    );
  }
}
