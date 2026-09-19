// 설정 화면. 기기마다 다른 값(출력 지연)과 데이터 관리(백업·휴지통)를 모아 둠.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../ads/ads.dart';
import '../core/db/settings_repo.dart';
import '../core/progress_dialog.dart';
import '../core/providers.dart';
import '../billing/purchases.dart';
import '../cloud/coin_wallet.dart';
import '../core/storage/backup.dart';
import '../score/import/import_sources.dart';
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

  /// 설정을 읽지 못한 사유. null이 아니면 목록 맨 위에 보여 줌.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 저장된 설정을 읽어 화면에 반영함. 읽지 못해도 기본값으로 화면을 열고 사유를 보여 줌.
  /// DB가 깨졌을 때 스피너에 머물면 되살리기 버튼에도 닿지 못함.
  Future<void> _load() async {
    final settings = ref.read(settingsRepoProvider);
    var ms = 0.0;
    var pedal = PedalKeys.defaults;
    String? error;
    try {
      ms = await settings.getDouble(kLatencyMsKey, 0);
      pedal = await loadPedalKeys(settings);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _latencyMs = ms;
      _pedal = pedal;
      _loadError = error;
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
              InputChip(label: Text(pedalKeyLabel(k)), onDeleted: () => _forgetPedal(k)),
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
  /// 만드는 동안 진행 대화상자로 막음. 다시 누르면 새 내보내기가 만들던 zip을 지움.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await runWithProgress(
        context,
        '백업 만드는 중',
        () => exportBackup(ref.read(dbProvider)),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Baton 백업'));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('백업 실패: $e')));
    }
  }

  /// 백업 zip을 골라 되살림. 되살린 뒤에는 앱을 다시 시작해야 함. 끝나면 선택기 사본을 지움.
  Future<void> _import() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['zip']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(importErrorMessage(e))));
      }
      return;
    }
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    try {
      await _restore(path);
    } finally {
      await discardImportSources(ImportSource.files, [path]);
    }
  }

  /// 고른 백업 zip으로 되살림. 확인을 받고 진행 표시를 띄움.
  Future<void> _restore(String path) async {
    if (!mounted) return;

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
    // 라이브러리를 통째로 갈아엎는 동안 아무 표시가 없으면 화면이 멈춘 것으로 보임
    String title;
    String message;
    try {
      await runWithProgress(
        context,
        '백업을 되살리는 중',
        () => importBackup(File(path), ref.read(dbProvider)),
      );
      title = '되살리기 완료';
      message = '앱을 완전히 닫았다가 다시 열어야 반영됨.';
    } on RestoreNeedsRestart catch (e) {
      // DB를 닫은 뒤 실패했거나 앞선 교체가 남아 있음. 되돌리기는 다음 시작 때 마침
      title = '되살리기 실패';
      message = '앱을 완전히 닫았다가 다시 열어야 함. 다시 열 때 원래 라이브러리로 되돌림.\n($e)';
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('되살리기 실패: $e')));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
      ),
    );
  }

  /// 복구 코드를 입력받아 다른 기기의 코인을 이 기기로 옮김. 입력의 대시·공백은 지갑이 맞춤.
  /// 이 기기에 남은 코인이 있거나 잔액을 확인하지 못하면 버려진다고 먼저 알리고,
  /// 이 기기의 복구 코드를 받아 둘 길을 줌.
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
    var result = await wallet.restore(code);
    if (!mounted) return;
    if (result == RestoreResult.wouldDiscard) {
      // lastError가 있으면 잔액을 확인하지 못한 경우라 버려질 코인 수를 모름
      final loss = wallet.lastError == null
          ? '가져오면 이 기기에 남은 ${wallet.balance}코인은 쓸 수 없게 됨.'
          : '${wallet.lastError}\n남은 코인이 있으면 가져오는 순간 쓸 수 없게 됨.';
      // true면 이 기기의 코드를 먼저 받아 둠, false면 그냥 버림, null이면 그만둠
      final saveFirst = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('이 기기의 코인이 버려짐'),
          content: Text('$loss\n이 기기의 복구 코드를 먼저 받아 두면 나중에 그 코드로 되찾을 수 있음.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('버리고 가져오기')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('코드 먼저 받기')),
          ],
        ),
      );
      if (saveFirst == null || !mounted) return;
      if (saveFirst && !await _issueRecoveryCode(wallet)) return;
      if (!mounted) return;
      result = await wallet.restore(code, discardCurrent: true);
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == RestoreResult.restored ? '코인을 가져옴' : (wallet.lastError ?? '가져오지 못함'),
        ),
      ),
    );
  }

  /// 복구 코드를 새로 받아 보여 주고, 적어 뒀다고 확인해야 서버에 적용함. 적용되면 true.
  /// 적용 전까지는 이전 코드가 그대로 통하므로 받기나 확인이 실패해도 코드를 잃지 않음.
  Future<bool> _issueRecoveryCode(CoinWallet wallet) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await wallet.issueRecoveryCode();
    if (!mounted) return false;
    if (code == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('복구 코드를 받지 못함: ${wallet.lastError ?? ''}\n이전 코드는 그대로 쓸 수 있음')),
      );
      return false;
    }
    final applied = await _showRecoveryCode(wallet, code);
    if (!mounted) return applied == true;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (applied) {
          true => '새 복구 코드로 바뀜. 이전 코드는 이제 쓸 수 없음',
          false => '새 코드를 적용하지 않음. 이전 코드를 그대로 씀',
          null => '적용됐는지 확인하지 못함. 복구 코드를 다시 받아 적어 둠',
        }),
      ),
    );
    return applied == true;
  }

  /// 복구 코드를 크게 보여 주고 '적어 뒀음'을 누르면 서버에 적용함. 바깥을 눌러 닫히지 않음.
  /// 적용되면 true, 적용을 시도하지 않고 닫으면 false, 시도가 실패한 채 닫으면 결과를 몰라 null.
  /// 적용은 같은 코드로 다시 보내도 안전하므로 실패하면 대화상자를 연 채 다시 누를 수 있음.
  Future<bool?> _showRecoveryCode(CoinWallet wallet, String code) async {
    String? error;
    var sending = false;
    var attempted = false;
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('복구 코드'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('기기를 바꿀 때 코인을 옮기는 유일한 방법임. 적어 두고 확인을 누르면 이전 코드는 쓸 수 없게 됨.'),
              const SizedBox(height: kGapL),
              SelectableText(
                code,
                style: Theme.of(ctx).textTheme.headlineSmall
                    ?.copyWith(fontFeatures: kTabular, letterSpacing: 2),
              ),
              if (error != null) ...[
                const SizedBox(height: kGapM),
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialog(() => sending = true);
                      attempted = true;
                      final ok = await wallet.confirmRecoveryCode(code);
                      if (!ctx.mounted) return;
                      if (ok) return Navigator.pop(ctx, true);
                      setDialog(() {
                        sending = false;
                        error = '적용하지 못함: ${wallet.lastError ?? ''}\n다시 누르면 이어서 적용함';
                      });
                    },
              child: const Text('적어 뒀음'),
            ),
          ],
        ),
      ),
    );
    if (applied == true) return true;
    return attempted ? null : false;
  }

  /// 구매 복원을 돌리고 결과를 알림. 복원할 것이 없거나 실패해도 조용히 끝나지 않게 함.
  Future<void> _restorePurchases(Purchases purchases) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await purchases.restore();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          PurchaseRestore.unlocked => '메트로놈 잠금 해제됨',
          PurchaseRestore.nothing => '이 스토어 계정에는 메트로놈 구매 기록이 없음',
          PurchaseRestore.failed => '구매 복원 실패: ${purchases.lastError ?? ''}',
        }),
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
                // 적립하지 못한 코인 구매가 남아 있으면 이때 다시 넣음
                await purchases.retryCoinPurchases();
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
      subtitle: const Text('기기를 바꿀 때 코인을 옮기는 유일한 방법. 적어 뒀다고 확인하면 이전 코드는 못 씀'),
      onTap: wallet.busy ? null : () => _issueRecoveryCode(wallet),
    ),
    for (final product in purchases.coinProducts)
      ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: Text(product.title.isEmpty ? product.id : product.title),
        subtitle: Text(product.description),
        trailing: FilledButton(
          // 등록 전에 사면 넣을 곳이 없어 결제만 됨. 지갑이 준비된 뒤에만 켬
          onPressed: purchases.busy || !wallet.ready ? null : () => purchases.buyCoins(product),
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
    // 코인 구매 정리 오류(purchases.coinError)도 메트로놈 구역이 아니라 여기 보임
    for (final error in [wallet.lastError, purchases.coinError].nonNulls)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGapL),
        child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                    if (_loadError != null)
                      ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('설정을 읽지 못해 기본값을 보여 줌'),
                        subtitle: Text(_loadError!),
                      ),
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
                        onPressed: purchases.busy ? null : () => _restorePurchases(purchases),
                        child: const Text('구매 복원'),
                      ),
                    ),
                    if (!purchases.unlocked && purchases.product != null)
                      ListTile(
                        leading: const Icon(Icons.shopping_bag_outlined),
                        title: const Text('메트로놈 잠금 해제'),
                        trailing: FilledButton(
                          onPressed: purchases.busy ? null : purchases.buy,
                          child: Text(purchases.product!.price),
                        ),
                      ),
                    if (purchases.lastError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: kGapL),
                        child: Text(
                          purchases.lastError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
