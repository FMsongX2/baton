// 설정 화면. 기기마다 다른 값(출력 지연)과 데이터 관리(백업·휴지통)를 모아 둠.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../ads/ads.dart';
import '../core/db/settings_repo.dart';
import '../core/providers.dart';
import '../billing/purchases.dart';
import '../cloud/coin_wallet.dart';
import '../core/storage/backup.dart';
import '../theme.dart';
import 'pedal_keys.dart';
import 'trash_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  double _latencyMs = 0;
  bool _loaded = false;
  PedalKeys _pedal = PedalKeys.defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 저장된 설정을 읽어 화면에 반영함.
  Future<void> _load() async {
    final settings = ref.read(settingsRepoProvider);
    final ms = await settings.getDouble(kLatencyMsKey, 0);
    final pedal = await loadPedalKeys(settings);
    if (!mounted) return;
    setState(() {
      _latencyMs = ms;
      _pedal = pedal;
      _loaded = true;
    });
  }

  /// 페달을 밟게 해서 어떤 키를 보내는지 배움. 배운 키는 고른 방향에 넣고 반대쪽에서는 뺌.
  Future<void> _learnPedal({required bool forward}) async {
    final key = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (ctx) => _PedalLearnDialog(forward: forward),
    );
    if (key == null || !mounted) return;
    final next = _pedal.assign(key, forward: forward);
    await savePedalKeys(ref.read(settingsRepoProvider), next);
    if (mounted) setState(() => _pedal = next);
  }

  /// 배운 키 하나를 지움.
  Future<void> _forgetPedal(LogicalKeyboardKey key) async {
    final next = _pedal.remove(key);
    await savePedalKeys(ref.read(settingsRepoProvider), next);
    if (mounted) setState(() => _pedal = next);
  }

  /// 매핑을 기본값으로 되돌림.
  Future<void> _resetPedal() async {
    await resetPedalKeys(ref.read(settingsRepoProvider));
    if (mounted) setState(() => _pedal = PedalKeys.defaults);
  }

  /// 페달 매핑 구역. 방향마다 배운 키를 칩으로 보여 주고 눌러서 지울 수 있게 함.
  List<Widget> _pedalSection() => [
    ListTile(
      leading: const Icon(Icons.keyboard_outlined),
      title: const Text('넘김 키'),
      subtitle: const Text('블루투스 페달은 키보드로 잡힘. 맞지 않으면 밟아서 새로 지정함'),
      trailing: TextButton(onPressed: _resetPedal, child: const Text('기본값')),
    ),
    _pedalRow('다음 페이지', _pedal.next, forward: true),
    _pedalRow('이전 페이지', _pedal.prev, forward: false),
  ];

  /// 방향 한 줄. 칩을 누르면 그 키를 지움.
  Widget _pedalRow(String label, Set<LogicalKeyboardKey> keys, {required bool forward}) => Padding(
    padding: const EdgeInsets.fromLTRB(kGapL, 0, kGapL, kGapM),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: kGapS),
        Wrap(
          spacing: kGapS,
          runSpacing: kGapS,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final k in keys)
              InputChip(label: Text(_keyLabel(k)), onDeleted: () => _forgetPedal(k)),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('밟아서 지정'),
              onPressed: () => _learnPedal(forward: forward),
            ),
          ],
        ),
      ],
    ),
  );

  /// 지연 보정을 저장함. 다음에 재생을 시작할 때부터 적용됨.
  Future<void> _saveLatency(double ms) =>
      ref.read(settingsRepoProvider).set(kLatencyMsKey, ms.toStringAsFixed(0));

  /// 라이브러리 전체를 zip으로 내보내 공유 시트로 넘김.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('백업 만드는 중')));
    try {
      final file = await exportBackup(ref.read(dbProvider));
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Baton 백업'));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('백업 실패: $e')));
    }
  }

  /// 백업 zip을 골라 되살림. 되살린 뒤에는 앱을 다시 시작해야 함.
  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (picked.isEmpty || picked.first.path == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('백업 되살리기'),
        content: const Text(
          '지금 있는 악보와 필기를 백업 내용으로 바꿈. 백업에 없는 악보는 사라짐.\n'
          '도중에 실패하면 원래 상태로 되돌림. 끝나면 앱을 다시 시작해야 함.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('되살리기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // 라이브러리를 통째로 갈아엎는 동안 아무 표시가 없으면 화면이 멈춘 것으로 보임
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: kGapL),
              Expanded(child: Text('백업을 되살리는 중')),
            ],
          ),
        ),
      ),
    );
    try {
      await importBackup(File(picked.first.path!), ref.read(dbProvider));
      navigator.pop();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('되살리기 완료'),
          content: const Text('앱을 완전히 닫았다가 다시 열어야 반영됨.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
        ),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('되살리기 실패: $e')));
    }
  }

  /// 복구 코드를 입력받아 다른 기기의 코인을 이 기기로 옮김.
  Future<void> _restoreCoins(CoinWallet wallet) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('코인 가져오기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('전에 쓰던 기기에서 본 복구 코드를 넣음. 옮기면 그 기기에서는 쓸 수 없게 됨.'),
            const SizedBox(height: kGapM),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('가져오기'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    final ok = await wallet.restore(code.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? '코인을 가져옴' : (wallet.lastError ?? '가져오지 못함'))));
  }

  /// 복구 코드를 새로 받아 보여 줌. 서버는 해시만 들고 있어 이미 발급한 코드를 다시 볼 수 없으므로
  /// 재발급으로 대신함. 이전 코드는 이 순간부터 통하지 않음.
  Future<void> _issueRecoveryCode(CoinWallet wallet) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await wallet.issueRecoveryCode();
    if (!mounted) return;
    if (!ok || wallet.recoveryCode == null) {
      messenger.showSnackBar(SnackBar(content: Text(wallet.lastError ?? '복구 코드를 받지 못함')));
      return;
    }
    await _showRecoveryCode(wallet, wallet.recoveryCode!);
  }

  /// 복구 코드를 크게 보여 줌. 이 코드를 잃으면 기기를 바꿀 때 코인을 되찾을 수 없음.
  Future<void> _showRecoveryCode(CoinWallet wallet, String code) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('복구 코드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('기기를 바꿀 때 코인을 옮기는 유일한 방법임. 적어 두길 권함.\n이전에 받은 코드는 이제 쓸 수 없음.'),
            const SizedBox(height: kGapL),
            SelectableText(
              code,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontFeatures: kTabular, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              wallet.dismissRecoveryCode();
              Navigator.pop(ctx);
            },
            child: const Text('적어 뒀음'),
          ),
        ],
      ),
    );
  }

  /// 코인 잔액과 구매, 기기 이전을 한 묶음으로 보여 줌.
  List<Widget> _coinSection(CoinWallet wallet, Purchases purchases) => [
    ListTile(
      leading: const Icon(Icons.toll_outlined),
      title: Text('${wallet.balance} 코인'),
      subtitle: Text(
        wallet.pricing == null ? '악보를 AI로 분석할 때 씀' : '악보 한 쪽 분석에 ${wallet.pricing!.coinsPerPage}코인',
      ),
      trailing: IconButton(
        tooltip: '잔액 새로고침',
        icon: const Icon(Icons.refresh),
        onPressed: wallet.busy
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                await wallet.refresh();
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(wallet.lastError ?? '잔액 ${wallet.balance}코인')),
                );
              },
      ),
    ),
    ListTile(
      leading: const Icon(Icons.key_outlined),
      title: const Text('복구 코드 받기'),
      subtitle: const Text('기기를 바꿀 때 코인을 옮기는 유일한 방법. 받으면 이전 코드는 못 씀'),
      // ponytail: v1에서는 서버 주소가 없어 이 구역이 트리에 없음.
      // AI·코인을 켤 때 되돌릴 수 없는 재발급 앞에 확인 단계를 먼저 붙일 것
      onTap: wallet.busy ? null : () => _issueRecoveryCode(wallet),
    ),
    for (final product in purchases.coinProducts)
      ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: Text(product.title.isEmpty ? product.id : product.title),
        subtitle: Text(product.description),
        trailing: FilledButton(
          onPressed: purchases.busy ? null : () => purchases.buyCoins(product),
          child: Text(product.price),
        ),
      ),
    if (purchases.coinProducts.isEmpty)
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('코인 상품을 불러오지 못함'),
        subtitle: Text('스토어에 상품이 등록되면 여기에 나타남'),
      ),
    ListTile(
      leading: const Icon(Icons.swap_horiz),
      title: const Text('다른 기기에서 코인 가져오기'),
      onTap: wallet.busy ? null : () => _restoreCoins(wallet),
    ),
    if (wallet.lastError != null)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGapL),
        child: Text(
          wallet.lastError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchasesProvider);
    final wallet = ref.watch(coinWalletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: ContentWidth(
                child: ListView(
                  children: [
                    const SectionHeader('소리'),
                    ListTile(
                      title: const Text('출력 지연 보정'),
                      subtitle: Text(
                        '${_latencyMs.round()} ms'
                        '  ·  블루투스는 소리가 늦으므로 그만큼 클릭을 앞당김',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Slider(
                        min: 0,
                        max: 400,
                        divisions: 40,
                        value: _latencyMs.clamp(0, 400),
                        label: '${_latencyMs.round()} ms',
                        onChanged: (v) => setState(() => _latencyMs = v),
                        onChangeEnd: _saveLatency,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final preset in const [
                            (0.0, '유선·스피커'),
                            (160.0, '블루투스'),
                            (250.0, '지연 큰 블루투스'),
                          ])
                            ActionChip(
                              label: Text(preset.$2),
                              onPressed: () {
                                setState(() => _latencyMs = preset.$1);
                                _saveLatency(preset.$1);
                              },
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    const SectionHeader('페달'),
                    ..._pedalSection(),
                    const Divider(),
                    const SectionHeader('메트로놈'),
                    ListTile(
                      leading: Icon(purchases.unlocked ? Icons.check_circle : Icons.lock_outline),
                      title: Text(purchases.unlocked ? '잠금 해제됨' : '잠김'),
                      subtitle: const Text('기기를 바꿨다면 구매 복원을 누름'),
                      trailing: TextButton(
                        onPressed: purchases.busy ? null : purchases.restore,
                        child: const Text('구매 복원'),
                      ),
                    ),
                    if (wallet.available) ...[
                      const Divider(),
                      const SectionHeader('코인'),
                      ..._coinSection(wallet, purchases),
                    ],
                    const Divider(),
                    const SectionHeader('데이터'),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('휴지통'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TrashPage()),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('백업 내보내기'),
                      subtitle: const Text('악보 파일과 필기를 zip 하나로 묶음'),
                      onTap: _export,
                    ),
                    ListTile(
                      leading: const Icon(Icons.unarchive_outlined),
                      title: const Text('백업 되살리기'),
                      onTap: _import,
                    ),
                    // 동의를 받은 지역(EEA 등)에서는 언제든 바꿀 수 있는 진입점이 있어야 함(UMP 요건)
                    ValueListenableBuilder<bool>(
                      valueListenable: Ads.privacyOptionsRequired,
                      builder: (context, required, _) => required
                          ? const ListTile(
                              leading: Icon(Icons.privacy_tip_outlined),
                              title: Text('광고 개인정보 옵션'),
                              onTap: Ads.showPrivacyOptions,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 키 이름을 사람이 읽을 수 있게. 이름이 없는 키는 코드로 보여 줌.
String _keyLabel(LogicalKeyboardKey key) =>
    key.keyLabel.isNotEmpty ? key.keyLabel : key.debugName ?? '키 ${key.keyId}';

/// 페달을 한 번 밟으면 그 키를 돌려주는 대화상자.
/// 여기서만 키를 먹으므로 배우는 동안 화면이 넘어가지 않음.
class _PedalLearnDialog extends StatelessWidget {
  const _PedalLearnDialog({required this.forward});

  final bool forward;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(forward ? '다음 페이지 키' : '이전 페이지 키'),
    content: Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        Navigator.pop(context, e.logicalKey);
        return KeyEventResult.handled;
      },
      child: const SizedBox(height: 72, child: Center(child: Text('지금 페달을 한 번 밟거나 키를 누름'))),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))],
  );
}
