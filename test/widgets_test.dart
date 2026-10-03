import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/ui/lock.dart';
import 'package:safe_vault/ui/common.dart';
import 'package:safe_vault/ui/app.dart';
import 'package:safe_vault/core/model.dart';

void main() {
  for (final length in [4, 6]) {
    testWidgets('PIN dots match configured length $length', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PinDots(length: length, entered: 2)),
        ),
      );
      for (var i = 0; i < length; i++) {
        expect(find.byKey(ValueKey('pin-dot-$i')), findsOneWidget);
      }
      expect(find.byKey(ValueKey('pin-dot-$length')), findsNothing);
    });
  }
  testWidgets('empty screen has an actionable first add', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            title: 'A fresh start',
            subtitle: 'Create a note.',
            add: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    expect(taps, 1);
  });
  testWidgets('long record names render without overflow in dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: vaultTheme(Brightness.dark),
        home: Scaffold(
          body: ItemTile(
            item: Item(
              id: 'x',
              kind: Kind.note,
              title: List.filled(15, 'A long title').join(' '),
              body: 'Details',
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
