import 'package:flutter/material.dart';
import 'design.dart';
import 'package:intl/intl.dart';

class ReminderPicker extends StatelessWidget {
  final bool enabled;
  final DateTime? selected;
  final void Function(bool, DateTime?) onChanged;
  const ReminderPicker({super.key, required this.enabled,
    required this.selected, required this.onChanged});
  Future<void> choose(BuildContext context) async {
    final now = DateTime.now();
    final seed = selected != null && selected!.isAfter(now) ? selected! : now;
    final date = await showDatePicker(context: context, initialDate: seed,
      firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(2200));
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context,
      initialTime: TimeOfDay.fromDateTime(seed));
    if (time == null || !context.mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!at.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a future time.')));
      return;
    }
    onChanged(true, at);
  }
  Future<void> customDelay(BuildContext context) async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final minutes = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remind me in…'),
      content: Form(key: form, child: TextFormField(controller: controller,
        autofocus: true, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Minutes', hintText: 'For example, 45'),
        validator: (v) { final n = int.tryParse(v ?? '');
          return n == null || n < 1 || n > 525600 ? 'Enter 1 to 525600 minutes' : null; })),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, int.parse(controller.text)); }, child: const Text('Set reminder'))]));
    // Dispose after the closing route's transition has completed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (minutes != null && context.mounted) onChanged(true, DateTime.now().add(Duration(minutes: minutes)));
  }
  @override
  Widget build(BuildContext context) => VaultCard(child: Padding(
    padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Reminder'),
        value: enabled,
        onChanged: (v) => onChanged(v, selected ?? (v ? DateTime.now().add(const Duration(minutes: 5)) : null))),
      if (enabled) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final minutes in [1, 5, 15, 30, 60])
            ActionChip(label: Text(minutes == 60 ? '1 hour' : '$minutes min'),
              onPressed: () => onChanged(true, DateTime.now().add(Duration(minutes: minutes)))),
          ActionChip(label: const Text('Custom'), onPressed: () => customDelay(context)),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () => choose(context), icon: const Icon(Icons.edit_calendar),
          label: const Text('Date & time')),
        if (selected != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(DateFormat('EEE, d MMM yyyy · h:mm:ss a').format(selected!.toLocal()),
            style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        const Text('Save to schedule.'),
      ],
    ])));
}
