import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/controller.dart';
import 'package:safe_vault/core/database.dart';
import 'package:safe_vault/core/crypto.dart';
import 'package:safe_vault/core/model.dart';
import 'package:safe_vault/core/repository.dart';
import 'package:safe_vault/core/reminders.dart';
import 'package:safe_vault/core/security.dart';
import 'package:safe_vault/ui/app.dart';

class ResumeSecurity extends SecurityService {
  Completer<bool>? pending;
  int calls=0;
  ResumeSecurity(){enabled=true;biometricEnabled=true;}
  @override Future<void> refreshBiometrics()async{}
  @override Future<bool> unlockBiometric()async{
    calls++;authenticating=true;pending=Completer<bool>();
    try{final result=await pending!.future;if(result)biometricSuccesses++;return result;}finally{authenticating=false;}
  }
  @override Future<bool> verify(String pin)async=>pin=='123456';
  @override Future<void> cancelBiometric()async{if(pending!=null&&!pending!.isCompleted)pending!.complete(false);}
}
class ResumeController extends VaultController {
  ResumeController(SecurityService s):super(VaultRepository(VaultDatabase(NativeDatabase.memory()),VaultCrypto()),s,ReminderService());
  @override Future<void> reconcile()async{}
}
void main(){
  for(final accepted in [true,false])testWidgets('background biometric result=$accepted restores usable foreground UI',(tester)async{
    final s=ResumeSecurity();final c=ResumeController(s)..lockSeconds=0..onboarding=true;
    addTearDown(c.repo.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(ProviderScope(overrides:[vaultProvider.overrideWithValue(c),itemsProvider.overrideWith((ref)=>Stream.value(<Item>[]))],
      child:SafeVaultApp(controller:c)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();await tester.pump();
    expect(c.locked,isTrue);expect(s.calls,1);
    // Native biometric prompt temporarily changes focus, then returns.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await tester.pump();
    s.pending!.complete(accepted);await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    if(!accepted){
      for(final digit in ['1','2','3','4','5','6']){await tester.tap(find.text(digit));await tester.pump();}
      await tester.pumpAndSettle();
    }
    expect(c.locked,isFalse);
    expect(find.byKey(const ValueKey('vault-privacy')),findsNothing);
    expect(find.byKey(const ValueKey('vault-lock')),findsNothing);
    await tester.tap(find.byIcon(Icons.tune));await tester.pumpAndSettle();
    expect(find.text('Security'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
