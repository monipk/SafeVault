import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/controller.dart';
import 'package:safe_vault/core/crypto.dart';
import 'package:safe_vault/core/database.dart';
import 'package:safe_vault/core/model.dart';
import 'package:safe_vault/core/reminders.dart';
import 'package:safe_vault/core/repository.dart';
import 'package:safe_vault/core/security.dart';
import 'package:safe_vault/ui/app.dart';
import 'package:safe_vault/ui/home.dart';
import 'package:safe_vault/ui/lock.dart';
import 'package:safe_vault/ui/settings.dart';

class FakeSecurity extends SecurityService {
  int biometricCalls = 0;
  bool acceptBiometric = false;
  FakeSecurity() { enabled = true; biometricEnabled = true; }
  @override
  Future<bool> unlockBiometric() async { biometricCalls++; return acceptBiometric; }
  @override
  Future<bool> verify(String pin) async => pin == '123456';
}
VaultController controller(SecurityService security) => VaultController(
  VaultRepository(VaultDatabase(NativeDatabase.memory()), VaultCrypto()), security, ReminderService());

void main() {
  testWidgets('biometrics opens once automatically; PIN works after cancellation', (tester) async {
    final security = FakeSecurity();
    final c = controller(security);
    addTearDown(c.repo.dispose);
    var unlocked = 0;
    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: c, onUnlocked: () => unlocked++)));
    await tester.pump();
    expect(security.biometricCalls, 1);
    for (final digit in ['1','2','3','4','5','6']) { await tester.tap(find.text(digit)); await tester.pump(); }
    expect(unlocked, 1);
    expect(security.biometricCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('forgot PIN has an inline recovery form', (tester) async {
    final security = FakeSecurity();
    final c = controller(security);
    addTearDown(c.repo.dispose);
    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: c, onUnlocked: () {})));
    await tester.pump();
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pump();
    expect(find.text('New PIN'), findsOneWidget);
    expect(find.text('Verify & reset'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final glass in [false, true]) {
    testWidgets('compact navigation and one Add at 320px; glass=$glass', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller(SecurityService());
      addTearDown(c.repo.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        vaultProvider.overrideWithValue(c), itemsProvider.overrideWith((ref) => Stream.value(<Item>[])),
      ], child: MaterialApp(theme: vaultTheme(Brightness.light, glass: glass),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
        home: const HomeScreen())));
      await tester.pumpAndSettle();
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.destinations.whereType<NavigationDestination>().map((d) => d.label), ['Home','Doc','Sub','Notes','Plan']);
      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      await tester.scrollUntilVisible(
  find.text('Guide'), 150,
  scrollable: find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.byType(Scrollable),
  ).first,
);
expect(find.text('Guide'), findsOneWidget);
await tester.scrollUntilVisible(
  find.text('Appearance'), -150,
  scrollable: find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.byType(Scrollable),
  ).first,
);
await tester.pumpAndSettle();
      expect(find.text('Send test'), findsNothing);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Glass cards'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsScreen), findsWidgets);
    });
  }
}
