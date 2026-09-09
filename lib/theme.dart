// 앱 전체 색·타이포·간격. 무대 조명 아래 보면대 위에서 쓰는 것을 기준으로 잡음.
// 액센트가 앰버인 이유: 어두운 곳에서 청색 계열은 암순응을 깨뜨려 악보 가독성을 떨어뜨림.

import 'package:flutter/material.dart';

/// 브랜드 액센트. 재생 중·선택 상태처럼 지금 무슨 일이 일어나는지 알리는 곳에만 씀.
/// 어두운 배경 전용임. 밝은 배경 위에서는 대비가 1.68:1로 읽히지 않음.
const kAccent = Color(0xFFFFB020);

/// 밝은 테마용 액센트. 같은 앰버 계열이되 스캐폴드 배경 대비 4.7:1, 그 위의 흰 글씨 5.1:1.
/// 조작줄을 숨겼을 때 재생 중임을 알리는 유일한 표시가 이 색이라 밝은 연습실에서도 읽혀야 함.
const kAccentInk = Color(0xFF9A6100);

/// 강박·경고처럼 한 단계 더 강한 신호. 어두운 배경 전용.
const kAccentStrong = Color(0xFFFF7043);

/// 밝은 테마용 강한 신호. 밝은 배경에서 kAccentStrong은 2.3:1이라 강박 표시가 구분되지 않음.
const kAccentStrongInk = Color(0xFFC43E17);

/// 완전한 검정은 OLED에서 스크롤 잔상이 생기므로 살짝 띄움.
const kDarkBackground = Color(0xFF0F0F13);
const kDarkSurface = Color(0xFF17171C);
const kDarkSurfaceHigh = Color(0xFF22222A);

/// 숫자가 자리마다 흔들리지 않게 함. BPM·마디·시간처럼 연주 중 읽는 값에 씀.
const kTabular = <FontFeature>[FontFeature.tabularFigures()];

/// 간격 단위. 4의 배수로만 씀.
const kGapXs = 4.0;
const kGapS = 8.0;
const kGapM = 12.0;
const kGapL = 16.0;
const kGapXl = 24.0;

/// 연주 중 누르는 버튼의 최소 크기. 일반 44dp보다 크게 잡음.
const kPlayControlSize = 56.0;

ThemeData batonTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // 액센트를 밝기별로 나눠 호출부를 건드리지 않고 대비를 맞춤.
  // primary 하나만 바꾸면 onPrimary(어두운 갈색)가 어두운 바탕에 얹혀 글씨가 사라지므로 짝으로 바꿈
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: brightness).copyWith(
    primary: dark ? kAccent : kAccentInk,
    onPrimary: dark ? const Color(0xFF241700) : Colors.white,
    secondary: dark ? kAccentStrong : kAccentStrongInk,
    surface: dark ? kDarkSurface : const Color(0xFFFBFAF7),
    surfaceContainerLowest: dark ? kDarkBackground : Colors.white,
    surfaceContainerHighest: dark ? kDarkSurfaceHigh : const Color(0xFFEFEDE7),
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: dark ? kDarkBackground : const Color(0xFFF7F5F1),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? kDarkBackground : const Color(0xFFF7F5F1),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? kDarkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      height: 64,
    ),
    chipTheme: base.chipTheme.copyWith(
      showCheckmark: false,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: base.textTheme.labelLarge?.copyWith(fontFeatures: kTabular),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: kGapM),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.4),
      space: 1,
      thickness: 1,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 4,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
    ),
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(fontFeatures: kTabular),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(fontFeatures: kTabular),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontFeatures: kTabular),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontFeatures: kTabular),
    ),
  );
}

/// 목록이 비었을 때 다음 행동까지 알려 주는 안내. 화면마다 문구만 바꿔 씀.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kGapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: kGapL),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: kGapS),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: kGapXl), action!],
          ],
        ),
      ),
    );
  }
}

/// 설정 목록의 구역 제목.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kGapL, kGapXl, kGapL, kGapS),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// 태블릿 가로처럼 넓은 화면에서 내용이 끝까지 퍼지지 않도록 가운데로 모음.
/// 설정 목록이나 메트로놈처럼 한 줄이 길어지면 읽기 어려운 화면에 씀.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
