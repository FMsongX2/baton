// 재생 컨트롤과 카운트인 표시. 매 프레임 바뀌는 값은 ValueListenable로만 갱신해
// 뷰어를 다시 빌드하지 않음. 연주 중 누르는 버튼이라 타깃을 크게 잡음.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../score/playback_engine.dart';
import '../theme.dart';

class PlaybackBar extends StatelessWidget {
  const PlaybackBar({
    super.key,
    required this.engine,
    required this.onJumpToSpan,
    this.onInteract,
    this.clickAvailable = true,
    this.clickOn = true,
    this.onToggleClick,
  });

  final PlaybackEngine engine;

  final void Function(int spanIndex) onJumpToSpan;

  /// 조작이 있었음을 알려 자동 숨김 시계를 다시 감게 함.
  final VoidCallback? onInteract;

  /// 메트로놈을 쓸 수 있는 상태인지. 미구매면 버튼을 잠금 표시로 바꿈.
  final bool clickAvailable;
  final bool clickOn;
  final VoidCallback? onToggleClick;

  @override
  Widget build(BuildContext context) {
    final tl = engine.timeline;
    final scheme = Theme.of(context).colorScheme;
    final ready = tl != null && tl.spans.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapS, kGapS, kGapS, kGapM),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: kGapS),
              ValueListenableBuilder<double>(
                valueListenable: engine.progressValue,
                builder: (_, v, _) => Expanded(
                  child: Slider(
                    value: v.clamp(0.0, 1.0),
                    onChanged: !ready
                        ? null
                        : (nv) {
                            onInteract?.call();
                            // 진행바를 끌면 가장 가까운 페이지 시작으로 붙임.
                            // 마디 중간으로 떨어지면 카운트가 어긋나 연주자가 따라갈 수 없음
                            final target = nv * tl.totalSeconds;
                            var i = 0;
                            for (var k = 0; k < tl.spans.length; k++) {
                              if (tl.spans[k].start <= target) i = k;
                            }
                            onJumpToSpan(i);
                          },
                  ),
                ),
              ),
              const SizedBox(width: kGapS),
              ValueListenableBuilder<int>(
                valueListenable: engine.spanIndex,
                builder: (_, i, _) => Text(
                  ready ? '${i + 1} / ${tl.spans.length}' : '-',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: kGapM),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '처음으로',
                iconSize: 26,
                icon: const Icon(Icons.skip_previous),
                onPressed: !ready
                    ? null
                    : () {
                        onInteract?.call();
                        engine.stop();
                      },
              ),
              const SizedBox(width: kGapL),
              ValueListenableBuilder<bool>(
                valueListenable: engine.isPlaying,
                builder: (_, playing, _) => SizedBox(
                  width: kPlayControlSize,
                  height: kPlayControlSize,
                  child: Semantics(
                    button: true,
                    label: playing ? '일시정지' : '재생',
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      onPressed: !ready
                          ? null
                          : () {
                              onInteract?.call();
                              playing ? engine.pause() : engine.play();
                            },
                      child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 32),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: kGapL),
              IconButton(
                tooltip: clickAvailable ? (clickOn ? '클릭 끄기' : '클릭 켜기') : '메트로놈 잠김',
                iconSize: 26,
                isSelected: clickOn,
                color: clickOn ? scheme.primary : null,
                icon: Icon(
                  clickAvailable
                      ? (clickOn ? Icons.volume_up : Icons.volume_off)
                      : Icons.lock_outline,
                ),
                onPressed: onToggleClick == null
                    ? null
                    : () {
                        onInteract?.call();
                        onToggleClick!();
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 조작줄을 숨긴 채 재생 중일 때 남는 유일한 표시. 화면 맨 위 가는 띠.
class PlaybackStrip extends StatelessWidget {
  const PlaybackStrip({super.key, required this.engine});

  final PlaybackEngine engine;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: engine.isPlaying,
    builder: (context, playing, _) {
      if (!playing) return const SizedBox.shrink();
      return ValueListenableBuilder<double>(
        valueListenable: engine.progressValue,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v.clamp(0.0, 1.0),
          minHeight: 3,
          backgroundColor: Colors.transparent,
        ),
      );
    },
  );
}

/// 카운트인 중에만 뜨는 큰 숫자. 악보에서 눈을 떼지 않고도 남은 박을 셀 수 있어야 함.
class CountInOverlay extends StatelessWidget {
  const CountInOverlay({super.key, required this.remaining});

  final ValueListenable<int?> remaining;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int?>(
      valueListenable: remaining,
      builder: (context, n, _) {
        if (n == null) return const SizedBox.shrink();
        // 화면 짧은 변에 맞춰 크기를 잡음. 고정 168px은 작은 화면에서 과하고
        // 글꼴 배율이 큰 기기에서는 숫자가 원을 뚫고 나감
        final size = (MediaQuery.sizeOf(context).shortestSide * 0.35).clamp(120.0, 200.0);
        return IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              // 박이 바뀔 때마다 살짝 커졌다 돌아와 시선을 끌지 않고도 셈이 됨
              key: ValueKey(n),
              tween: Tween(begin: 1.18, end: 1.0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              // 원 크기를 화면에서 뽑았으므로 글꼴 배율은 적용하지 않음. 그러지 않으면 숫자가 원을 뚫음
              child: MediaQuery.withNoTextScaling(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.86),
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: size * 0.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                      fontFeatures: kTabular,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
