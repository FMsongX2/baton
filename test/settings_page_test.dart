// 설정 화면이 설정을 읽지 못해도 열리는지 검증. DB가 깨졌을 때 스피너에 머물면
// 복구 수단인 백업 되살리기에도 닿지 못함.

import 'package:baton/billing/purchases.dart';
import 'package:baton/cloud/api_client.dart';
import 'package:baton/cloud/coin_wallet.dart';
import 'package:baton/core/db/database.dart';
import 'package:baton/core/db/settings_repo.dart';
import 'package:baton/core/providers.dart';
import 'package:baton/settings/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 읽을 때마다 던지는 설정 저장소. 손상된 DB를 흉내 냄.
class _BrokenSettings extends SettingsRepo {
  _BrokenSettings(super.db);

  /// 언제나 손상 오류를 던짐.
  @override
  Future<String?> get(String key) => Future.error(StateError('database disk image is malformed'));
}

void main() {
  testWidgets('설정을 읽지 못해도 기본값으로 열리고 백업 되살리기에 닿음', (tester) async {
    final db = BatonDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = _BrokenSettings(db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(settings),
          // 스토어·서버에 묻지 않게 init 없이 둠
          purchasesProvider.overrideWith((ref) => Purchases(settings)),
          coinWalletProvider.overrideWith((ref) => CoinWallet(ApiClient())),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('설정을 읽지 못해 기본값을 보여 줌'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('백업 되살리기'), 200);
    expect(find.text('백업 되살리기'), findsOneWidget);
  });
}
