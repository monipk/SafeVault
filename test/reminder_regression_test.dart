import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/model.dart';
import 'package:safe_vault/ui/reminder_picker.dart';

void main() {
  test('old encrypted records work without a reminderAt field', () {
    final old = Item(id: 'old', kind: Kind.document, title: 'Passport',
      due: DateTime(2030, 1, 1), remind: true, leadDays: 1, reminderMinute: 1380).toJson()
      ..remove('reminderAt');
    final loaded = Item.fromJson(old);
    expect(loaded.reminderTime, DateTime(2029, 12, 31, 23));
  });
  test('one minute reminder retains seconds and works without a due date', () {
    final now = DateTime(2030, 1, 1, 9, 12, 44);
    final item = Item(id: 'note', kind: Kind.note, title: 'Call', remind: true,
      reminderAt: now.add(const Duration(minutes: 1)));
    final restored = Item.fromJson(item.toJson());
    expect(restored.reminderTime!.difference(now), const Duration(minutes: 1));
    expect(restored.due, isNull);
    expect(restored.patch({'remind': false}).reminderTime, isNull);
  });
  test('completing a monthly item preserves reminder calendar offset', () {
    final item = Item(id: 'm', kind: Kind.task, title: 'Renew', due: DateTime(2028, 1, 31),
      remind: true, reminderAt: DateTime(2028, 1, 30, 23, 58, 11), cycle: 'Monthly');
    expect(nextReminderFor(item, DateTime(2028, 2, 29)), DateTime(2028, 2, 28, 23, 58, 11));
  });
  test('trash, pause, archive and completion suppress eligible reminders', () {
    final item = Item(id: 'a', kind: Kind.task, title: 'A', remind: true, reminderAt: DateTime(2030));
    expect(item.active, isTrue);
    for (final patch in [<String, dynamic>{'done': true}, {'archived': true},
      {'deleted': DateTime(2029).toIso8601String()}, {'status': 'Paused'}]) {
      expect(item.patch(patch).active, isFalse);
    }
  });
  testWidgets('one minute quick choice keeps precision and updates selected time', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReminderPicker(enabled: true,
      selected: null, onChanged: (_, value) => selected = value))));
    final before = DateTime.now();
    await tester.tap(find.text('1 min'));
    final after = DateTime.now();
    expect(selected!.isBefore(before.add(const Duration(minutes: 1))), isFalse);
    expect(selected!.isAfter(after.add(const Duration(minutes: 1))), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('enabling a reminder supplies a future default time', (tester) async {
    bool? enabled;
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReminderPicker(enabled: false,
      selected: null, onChanged: (on, value) { enabled = on; selected = value; }))));
    await tester.tap(find.byType(Switch));
    expect(enabled, isTrue);
    expect(selected!.isAfter(DateTime.now()), isTrue);
  });
}
