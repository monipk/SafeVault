import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/controller.dart';
import '../core/model.dart';
import 'common.dart';
import 'design.dart';
import 'detail.dart';
import 'settings.dart';
import 'reminder_picker.dart';
import 'item_tools.dart';
import '../core/reminder_rules.dart';

class ReminderCenter extends ConsumerStatefulWidget {
  const ReminderCenter({super.key});
  @override
  ConsumerState<ReminderCenter> createState() => _ReminderCenterState();
}
class _ReminderCenterState extends ConsumerState<ReminderCenter> {
  bool busy = false;
  int limit = 60;
  String filter = 'All';
  DateTime nextTime(Item item) {
    final times=item.reminderTimes;
    final now=DateTime.now();
    return times.where((at)=>at.isAfter(now)).firstOrNull ?? times.last;
  }
  DateTime shownTime(Item item, VaultController c) => c.quiet
    ? outsideQuietHours(nextTime(item),c.quietStart,c.quietEnd) : nextTime(item);
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await attempt(context, action);
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(vaultProvider);
    final data = ref.watch(itemsProvider);
    return ListenableBuilder(listenable: c, builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Reminders'), actions: [IconButton(
        tooltip: 'Reminder settings', icon: const Icon(Icons.tune),
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen(section: 'Reminders'))))]),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (busy) const LinearProgressIndicator(),
          if (!c.notifications || c.reminders.warning != null) VaultCard(child: ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(c.notifications ? 'Check notification permissions' : 'Notifications are off'),
            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen(section: 'Reminders'))))),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final value in ['All','Upcoming','Past due'])
            ChoiceChip(label: Text(value), selected: filter == value,
              onSelected: (_) => setState(() { filter = value; limit = 60; }))]),
          const SizedBox(height: 16),
          data.when(loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => TextButton(onPressed: () => ref.invalidate(itemsProvider), child: const Text('Could not load. Retry')),
            data: (items) {
              final now = DateTime.now();
              final reminders = items.where((i) => i.active && i.reminderTimes.isNotEmpty &&
                (filter == 'All' || (filter == 'Upcoming' ? shownTime(i,c).isAfter(now) : !shownTime(i,c).isAfter(now))))
                .toList()..sort((a,b) => shownTime(a,c).compareTo(shownTime(b,c)));
              if (reminders.isEmpty) return const EmptyState(title: 'All clear', subtitle: 'Add a reminder to any item.', icon: Icons.notifications_none);
              return Column(children: [for (final item in reminders.take(limit)) reminderCard(item, c),
                if (reminders.length > limit) TextButton(onPressed: () => setState(() => limit += 60), child: const Text('Load more'))]);
            }),
        ])))));
  }
  Future<void> snooze(Item item, int delay) async {
    DateTime? at;
    if (delay > 0) { at = DateTime.now().add(Duration(minutes: delay)); }
    else {
      final now = DateTime.now();
      at = DateTime(now.year, now.month, now.day + 1, 9);
      if (delay == 0) {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
          title: const Text('Snooze until'), content: SizedBox(width: 440, child: SingleChildScrollView(child: ReminderPicker(
            enabled: true, selected: at, onChanged: (_, value) => update(() => at = value)))), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))])));
        if (ok != true || at == null) return;
      }
    }
    final c = ref.read(vaultProvider);
    final latest = await currentItem(c,item.id);
    final target = nextTime(latest);
    if (target == latest.reminderTime) {
      await c.save(latest.patch({'reminderAt': at!.toUtc().toIso8601String(), 'remind': true}));
    } else {
      await c.save(latest.withExtra({'alerts': latest.additionalReminders.map((time) =>
        (time == target ? at! : time).toUtc().toIso8601String()).toList()}));
    }
  }
  Widget reminderCard(Item item, VaultController c) => VaultCard(child: Padding(
    padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), leading: Icon(kindIcon(item.kind)),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(DateFormat('d MMM · h:mm a').format(shownTime(item,c).toLocal())),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => ItemDetail(id: item.id)))),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PopupMenuButton<int>(enabled: !busy, tooltip: 'Snooze', onSelected: (delay) => run(() => snooze(item,delay)),
          itemBuilder: (_) => [for (final delay in [1,5,15,60,10080,-1,0]) PopupMenuItem(value: delay,
            child: Text(switch(delay) {60 => '1 hour',10080 => 'Next week',-1 => 'Tomorrow · 9 AM',0 => 'Choose time',_ => '$delay min'}))],
          child: const Padding(padding: EdgeInsets.all(12), child: Row(mainAxisSize: MainAxisSize.min,
            children: [Icon(Icons.snooze, size: 18), SizedBox(width: 6), Text('Snooze')]))),
        TextButton(onPressed: busy ? null : () => run(() => c.save(item.patch({'remind': false}))), child: const Text('Dismiss')),
        if (item.kind == Kind.task || item.kind == Kind.subscription)
          FilledButton.tonal(onPressed: busy ? null : () => run(() => c.complete(item)),
            child: Text(item.kind == Kind.subscription ? 'Paid' : 'Done')),
      ]),
    ])));
}
