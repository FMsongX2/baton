// 재생 컨트롤과 카운트인 표시. 매 프레임 바뀌는 값은 ValueListenable로만 갱신해
// 뷰어를 다시 빌드하지 않음. 연주 중 누르는 버튼이라 타깃을 크게 잡음.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../score/playback_engine.dart';
import '../score/timeline.dart';
import '../theme.dart';

class PlaybackBar extends StatelessWidget {
  /// 엔진과 넘김 콜백을 받음. locked면 위치를 옮기는 조작을 막고, onToggleClick이 null이면 클릭 버튼을 끔.
  const PlaybackBar({
    super.key,
    required this.engine,
    required this.onJumpToSpan,
    this.onInteract,
    this.locked = false,
    this.clickAvailable = true,
    this.clickOn = true,
    this.onToggleClick,
  });

  final PlaybackEngine engine;

  final void Function(int spanIndex) onJumpToSpan;

  /// 조작이 있었음을 알려 자동 숨김 시계를 다시 감게 함.
  final VoidCallback? onInteract;

  /// 터치 잠금 중인지. 잠그면 위치를 옮기는 조작(진행바·처음으로)을 막음.
  final bool locked;

  /// 메트로놈을 쓸 수 있는 상태인지. 미구매면 버튼을 잠금 표시로 바꿈.
  final bool clickAvailable;
  final bool clickOn;
  final VoidCallback? onToggleClick;

  /// 재생 여부가 바뀔 때마다 버튼을 다시 그림.
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<bool>(valueListenable: engine.isPlaying, builder: _build);

  /// 재생 여부에 따라 버튼을 그림. 재생 중이거나 잠겨 있으면 위치를 옮기는 조작을 막음.
  /// 연주 중에 잘못 누르면 멈춘 자리를 되찾을 길이 없어 연주가 통째로 무너짐.
  Widget _build(BuildContext context, bool playing, Widget? _) {
    final tl = engine.timeline;
    final scheme = Theme.of(context).colorScheme;
    final ready = tl != null && tl.spans.isNotEmpty;
    final canSeek = ready && !playing && !locked;

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
                    onChanged: !canSeek
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
                onPressed: !canSeek
                    ? null
                    : () {
                        onInteract?.call();
                        engine.stop();
                      },
              ),
              const SizedBox(width: kGapL),
              SizedBox(
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

/// 지금 떠 있는 쪽이 다음 넘김까지 얼마나 왔는지(0~1)와 넘김이 한 마디 안으로 다가왔는지.
/// 앞 쪽이 넘어온 시각부터 이 쪽이 넘어갈 시각까지를 한 구간으로 봄. 마지막 쪽은 곡 끝까지 채우고 예고하지 않음.
/// 앞뒤 쪽은 자동 넘김과 같은 이웃(playedNeighbor)으로 셈. 0마디 스팬으로는 넘기지 않으므로 끝의 빈 쪽 앞은
/// 마지막 쪽이고, 가운데 빈 쪽 뒤의 쪽은 빈 쪽 앞 쪽의 넘김부터 차오름.
({double progress, bool soon}) pageTurnProgress(Timeline t, int spanIndex, double now) {
  if (t.spans.isEmpty) return (progress: 0.0, soon: false);
  final i = spanIndex.clamp(0, t.spans.length - 1);
  final span = t.spans[i];
  final last = t.playedNeighbor(i) < 0;
  final prev = t.playedNeighbor(i, step: -1);
  final from = prev < 0 ? 0.0 : t.spans[prev].turnAt;
  final to = last ? span.end : span.turnAt;
  final progress = to > from ? ((now - from) / (to - from)).clamp(0.0, 1.0) : 1.0;
  final soon = !last && now < to && to - now <= barSeconds(span.clicksPerBar, span.bpm);
  return (progress: progress, soon: soon);
}

/// 조작줄을 숨긴 채 재생 중일 때 남는 표시. 화면 맨 위 가는 띠가 지금 쪽의 넘김까지 차오름.
/// 넘김 한 마디 전부터 굵어지고 경고색으로 바뀌어, 마디수가 틀린 쪽에서도 넘김을 미리 보고 페달로 맞출 수 있음.
/// 반전 무대에서는 어두운 테마 색을 따르므로 밝게 번쩍이지 않음.
class PlaybackStrip extends StatelessWidget {
  const PlaybackStrip({super.key, required this.engine});

  final PlaybackEngine engine;

  /// 재생 중에만 띠를 그림. 진행률 알림이 매 프레임 오므로 그 신호에 맞춰 넘김 진행을 다시 셈.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: engine.isPlaying,
    builder: (context, playing, _) {
      final t = engine.timeline;
      if (!playing || t == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return ValueListenableBuilder<double>(
        valueListenable: engine.progressValue,
        builder: (context, _, _) {
          final turn = pageTurnProgress(
            t,
            engine.spanIndex.value,
            engine.position.inMicroseconds / 1e6,
          );
          return LinearProgressIndicator(
            value: turn.progress,
            minHeight: turn.soon ? 6 : 3,
            color: turn.soon ? scheme.secondary : scheme.primary,
            backgroundColor: Colors.transparent,
          );
        },
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
