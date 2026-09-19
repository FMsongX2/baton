// 독립 메트로놈 화면. 악보 없이 템포만 맞출 때 씀.
// 재생 위치 계산과 클릭 예약은 악보 재생과 같은 클럭·스케줄러를 그대로 재사용함.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../billing/purchases.dart';
import '../core/db/settings_repo.dart';
import '../core/providers.dart';
import '../score/timeline.dart';
import '../theme.dart';
import 'click_scheduler.dart';

/// 한 번에 펼쳐 두는 마디 수. 이만큼 치면 다시 처음부터 예약함.
const _loopBars = 512;

class MetronomePage extends ConsumerStatefulWidget {
  const MetronomePage({super.key, this.active = true});

  /// 이 화면이 지금 보이는지. 탭을 벗어나도 위젯이 살아 있어 스스로 멈추지 못함.
  final bool active;

  @override
  ConsumerState<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends ConsumerState<MetronomePage> with SingleTickerProviderStateMixin {
  late final _audio = ref.read(audioProvider);
  late final _clock = _audio.createClock();
  late final _scheduler = ClickScheduler(_audio.soloud, _clock);
  late final Ticker _ticker;

  double _bpm = 120;
  int _clicksPerBar = 4;
  int _subdivision = 1;
  double _volume = 0.9;
  bool _running = false;

  /// 화면에 표시할 현재 박. 멈춘 뒤에도 마지막 값이 남으므로 표시는 _running과 함께 판단함.
  final _beat = ValueNotifier<int>(-1);

  List<Click> _clicks = const [];
  final _taps = <DateTime>[];

  @override
  void initState() {
    super.initState();
    _scheduler.accent = _audio.accent;
    _scheduler.tick = _audio.tick;
    _ticker = createTicker((_) => _onFrame());
    if (widget.active) WakelockPlus.enable();
    _loadLatency();
  }

  /// 저장된 지연 보정을 읽어 스케줄러에 넣음.
  Future<void> _loadLatency() async {
    final ms = await ref.read(settingsRepoProvider).getDouble(kLatencyMsKey, 0);
    _scheduler.latency = Duration(microseconds: (ms * 1000).round());
  }

  /// 다른 탭으로 넘어가면 멈춤. 그대로 두면 악보 재생과 클릭이 겹쳐 들림.
  /// 이어질 build가 화면을 맞춰 주므로 여기서 setState를 부르지 않음.
  @override
  void didUpdateWidget(MetronomePage old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      // 연습 중 화면이 꺼지면 BPM과 박 표시가 사라짐. 소리만 남아 쓸모가 없음
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
      if (_running) _stop();
    }
  }

  @override
  void dispose() {
    // 재생 중에 트리에서 빠지면 아무도 멈춰 주지 않음. 활성 Ticker를 dispose하면 assert에 걸림
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    _scheduler.cancelPending();
    _beat.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  /// 현재 설정으로 클릭을 다시 펼치고 처음부터 예약함.
  void _rebuild() {
    _clicks = metronomeClicks(
      bpm: _bpm,
      clicksPerBar: _clicksPerBar,
      bars: _loopBars,
      subdivision: _subdivision,
    );
    _scheduler.volume = _volume;
    _scheduler.load(_clicks, _clock.position);
  }

  /// 클릭을 멈추고 위치를 0으로 되돌림. 다음 시작이 강박부터 나오게 함.
  /// 화면 갱신은 부르는 쪽이 맡음.
  void _stop() {
    _running = false;
    _ticker.stop();
    _clock.pause();
    _clock.reset();
    _scheduler.cancelPending();
  }

  /// 시작·정지를 뒤집음.
  void _toggle() {
    if (_running) {
      setState(_stop);
      return;
    }
    setState(() {
      _running = true;
      _scheduler.cancelPending();
      _clock.reset();
      _rebuild();
      _clock.start();
      _ticker.start();
    });
  }

  /// 설정이 바뀌면 재생 중이라도 즉시 반영함. 템포가 바뀌면 박을 처음부터 다시 셈.
  void _apply(VoidCallback change) {
    setState(change);
    if (!_running) return;
    _scheduler.cancelPending();
    _clock.reset();
    _rebuild();
    _clock.start();
  }

  /// 매 프레임 클릭을 예약하고 화면의 박 표시를 갱신함.
  void _onFrame() {
    _scheduler.pump();
    final now = _clock.position.inMicroseconds / 1e6;
    final beatLen = 60.0 / _bpm;
    final total = _clicksPerBar;
    // 이음매 직후에는 위치가 잠깐 음수라 나머지 연산을 양수로 접어 줌
    _beat.value = total == 0 ? -1 : ((now ~/ beatLen) % total + total) % total;

    // 펼쳐 둔 마디를 다 쓰기 전에 이어 붙임. 다 쓴 뒤에 하면 새 루프의 첫 강박이
    // 이미 지난 시각이 되어 버려짐. 룩어헤드 안에 들어오면 미리 넘김
    final loopLength = _clicks.isEmpty ? 0.0 : _clicks.last.time + beatLen / _subdivision;
    final lookaheadSec = _scheduler.lookahead.inMicroseconds / 1e6;
    if (loopLength > 0 && now + lookaheadSec >= loopLength) {
      _clock.shift(secondsToDuration(loopLength));
      // 위치가 음수가 되므로 커서를 처음으로 되돌려야 첫 강박부터 예약됨
      _scheduler.load(_clicks, Duration.zero);
    }
  }

  /// 탭 간격의 중앙값으로 템포를 잡음. 평균은 한 번 잘못 누르면 크게 흔들림.
  void _tapTempo() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inSeconds > 3) _taps.clear();
    _taps.add(now);
    if (_taps.length > 8) _taps.removeAt(0);
    if (_taps.length < 2) return;
    final gaps = <int>[
      for (var i = 1; i < _taps.length; i++) _taps[i].difference(_taps[i - 1]).inMilliseconds,
    ]..sort();
    final mid = gaps[gaps.length ~/ 2];
    if (mid <= 0) return;
    _apply(() => _bpm = (60000 / mid).clamp(30, 300));
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchasesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('메트로놈')),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          child: Stack(
            children: [
              // Opacity는 시맨틱을 지우지 않아 스크린리더가 못 쓰는 컨트롤을 정상처럼 읽음
              ExcludeSemantics(
                excluding: !purchases.unlocked,
                child: AbsorbPointer(
                  absorbing: !purchases.unlocked,
                  child: Opacity(
                    opacity: purchases.unlocked ? 1 : 0.25,
                    child: Column(
                      children: [
                        Expanded(child: _controls()),
                        _playRow(),
                      ],
                    ),
                  ),
                ),
              ),
              if (!purchases.unlocked) _lockOverlay(purchases),
            ],
          ),
        ),
      ),
    );
  }

  /// 메트로놈 본체 UI.
  Widget _controls() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SizedBox(height: kGapL),
      ValueListenableBuilder<int>(
        valueListenable: _beat,
        builder: (_, beat, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _clicksPerBar; i++)
              _BeatDot(active: _running && beat == i, accent: i == 0),
          ],
        ),
      ),
      const SizedBox(height: kGapXl),
      Center(
        child: Text(
          _bpm.round().toString(),
          style: TextStyle(
            fontSize: 96,
            height: 1,
            fontWeight: FontWeight.w700,
            fontFeatures: kTabular,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      Center(
        child: Text(
          'BPM',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(letterSpacing: 3, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      Row(
        children: [
          IconButton(
            tooltip: '템포 1 낮춤',
            icon: const Icon(Icons.remove),
            onPressed: () => _apply(() => _bpm = (_bpm - 1).clamp(30, 300)),
          ),
          Expanded(
            child: Slider(
              min: 30,
              max: 300,
              value: _bpm,
              onChanged: (v) => setState(() => _bpm = v),
              onChangeEnd: (v) => _apply(() => _bpm = v),
            ),
          ),
          IconButton(
            tooltip: '템포 1 올림',
            icon: const Icon(Icons.add),
            onPressed: () => _apply(() => _bpm = (_bpm + 1).clamp(30, 300)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _chips(
        '마디당 클릭',
        const [2, 3, 4, 5, 6, 7],
        _clicksPerBar,
        (v) => _apply(() => _clicksPerBar = v),
      ),
      _chips(
        '분할',
        const [1, 2, 3, 4],
        _subdivision,
        (v) => _apply(() => _subdivision = v),
        labels: const {1: '없음', 2: '8분', 3: '셋잇단', 4: '16분'},
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.volume_up),
          Expanded(
            child: Slider(
              value: _volume,
              onChanged: (v) => setState(() {
                _volume = v;
                _scheduler.volume = v;
              }),
            ),
          ),
        ],
      ),
    ],
  );

  /// 시작·탭 줄. 목록 밖 아래에 고정해 화면이 작거나 광고 칸이 붙어도 스크롤 없이 누를 수 있게 함.
  Widget _playRow() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: kPlayControlSize,
                child: FilledButton.icon(
                  onPressed: _toggle,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow, size: 26),
                  label: Text(_running ? '정지' : '시작'),
                ),
              ),
            ),
            const SizedBox(width: kGapM),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: kPlayControlSize,
                child: OutlinedButton.icon(
                  onPressed: _tapTempo,
                  icon: const Icon(Icons.touch_app_outlined),
                  label: const Text('탭'),
                ),
              ),
            ),
          ],
        ),
        if (!_audio.ready)
          const Padding(padding: EdgeInsets.only(top: 16), child: Text('오디오 엔진을 열지 못해 소리가 나지 않음')),
      ],
    ),
  );

  /// 값 목록을 칩으로 고르는 구역. 칩이 줄바꿈되면 옆에 둔 라벨과 어긋나므로 위에 둠.
  Widget _chips<T>(
    String label,
    List<T> values,
    T current,
    void Function(T) onPick, {
    Map<T, String>? labels,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: kGapS),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: kGapS),
        Wrap(
          spacing: kGapS,
          runSpacing: kGapS,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labels?[v] ?? '$v'),
                selected: current == v,
                onSelected: (_) => onPick(v),
              ),
          ],
        ),
      ],
    ),
  );

  /// 미구매 상태에서 덮는 안내. 화면 가운데를 가리면 무엇을 사는지 안 보이므로
  /// 아래쪽에 붙이고 위쪽 메트로놈 UI가 그대로 보이게 둠.
  Widget _lockOverlay(Purchases purchases) => Align(
    alignment: Alignment.bottomCenter,
    // 가로 폰에 광고 칸까지 붙으면 카드가 남은 높이보다 커져 구매 버튼이 잘림
    child: SingleChildScrollView(
      child: Card(
        margin: const EdgeInsets.all(kGapL),
        child: Padding(
          padding: const EdgeInsets.all(kGapL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 20),
                  const SizedBox(width: kGapS),
                  Text('메트로놈', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: kGapS),
              Text(
                '한 번 사면 계속 씀. 악보 자동 넘김은 결제 없이 그대로 쓸 수 있음.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: kGapM),
              if (purchases.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    purchases.lastError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: purchases.busy || purchases.product == null ? null : purchases.buy,
                  child: Text(
                    purchases.product == null ? '스토어 확인 중' : '${purchases.product!.price}에 잠금 해제',
                  ),
                ),
              ),
              TextButton(
                onPressed: purchases.busy ? null : purchases.restore,
                child: const Text('구매 복원'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 박자 표시 점. 강박은 크게 두고, 칠 때 살짝 커져 곁눈으로도 박이 보이게 함.
class _BeatDot extends StatelessWidget {
  const _BeatDot({required this.active, required this.accent});

  final bool active;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = accent ? 26.0 : 18.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGapXs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: active ? size * 1.3 : size,
        height: active ? size * 1.3 : size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? (accent ? scheme.secondary : scheme.primary)
              : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
