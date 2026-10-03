import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup.dart';
import '../core/controller.dart';
import '../core/model.dart';
import 'common.dart';
import 'design.dart';
import 'organizer_settings.dart';
import 'lock.dart';
import 'reminder_center.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final String? section;
  const SettingsScreen({super.key, this.section});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool busy = false;
  Future<void> run(Future<void> Function() f) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    await attempt(context, f);
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<bool> authenticate(VaultController c) async {
    if (!c.security.enabled) {
      return true;
    }
    return await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Verify your identity')),
              body: LockScreen(
                controller: c,
                onUnlocked: () => Navigator.pop(context, true),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<String?> password({required bool creating}) async {
    final a = TextEditingController(), b = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(creating ? 'Protect your backup' : 'Unlock backup'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                creating
                    ? 'Use at least 12 characters. Keep this password safe; it cannot be recovered.'
                    : 'Enter the password used when this backup was created.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: a,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Backup password'),
                validator: (v) =>
                    v == null || v.isEmpty || (creating && v.length < 12)
                    ? 'Enter ${creating ? 'at least 12 characters' : 'your password'}'
                    : null,
              ),
              if (creating) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: b,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  validator: (v) =>
                      v == a.text ? null : 'Passwords do not match',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, a.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    // Dispose after the route transition, since the closing dialog still references these.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    a.dispose();
    b.dispose();
    return result;
  }

  Future<void> backup(VaultController c) async {
    final p = await password(creating: true);
    if (p == null) {
      return;
    }
    final bytes = await c.backups.create(p);
    if (await c.files.save(
      'safe-vault-${dateKey(DateTime.now())}.safevault',
      bytes,
    )) {
      await c.repo.setPreference(
        'lastBackup',
        DateTime.now().toIso8601String(),
      );
      if (mounted) {
        toast(context, 'Encrypted backup saved.');
      }
    }
  }

  Future<void> restore(VaultController c) async {
    if (!await authenticate(c)) {
      return;
    }
    final file = await c.files.pick(maxBytes: 80 * 1024 * 1024);
    if (file == null || !mounted) {
      return;
    }
    final p = await password(creating: false);
    if (p == null) {
      return;
    }
    final data = await c.backups.preview(file.bytes, p);
    if (!mounted) {
      return;
    }
    final counts = Kind.values
        .map(
          (k) =>
              '${data.items.where((i) => i.kind == k).length} ${k.label.toLowerCase()}',
        )
        .join('\n');
    if (!await confirm(
      context,
      'Restore this backup?',
      '$counts\n${data.attachments.length + data.assets.length} files and versions\n\nThis replaces ALL current records, including trash. Your PIN and settings stay unchanged. Export a backup first if needed.',
      action: 'Replace and restore',
    )) {
      return;
    }
    await c.mutate(() => c.repo.restore(data.items, data.attachments, assets: data.assets));
    if (mounted) {
      toast(context, 'Backup restored successfully.');
    }
  }

  Future<void> export(VaultController c, bool pdf) async {
    if (!await confirm(
      context,
      'Export unencrypted ${pdf ? 'summary' : 'CSV'}?',
      'The exported file will be readable by anyone who has it. ${pdf ? 'Notes and attachments are excluded.' : 'Notes are included; attachments are excluded.'}',
      action: 'Export',
    )) {
      return;
    }
    final items = (await c.repo.all())
        .where((i) => i.deleted == null && !i.archived)
        .toList();
    final bytes = pdf
        ? await BackupService.summary(items)
        : BackupService.csv(items);
    await c.files.save(
      'safe-vault-summary.${pdf ? 'pdf' : 'csv'}',
      bytes,
      mime: pdf ? 'application/pdf' : 'text/csv',
    );
  }

  Future<void> recovery(VaultController c) async {
    if (!await authenticate(c) || !mounted) return;
    final code = c.security.newRecoveryCode();
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Save recovery code'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Write this down and keep it outside this app. It can reset your PIN once. A new code replaces your previous one.'),
        const SizedBox(height: 20), SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 19)),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I saved it'))]));
    if (accepted == true) { await c.security.setRecoveryCode(code); c.refresh();
      if (mounted) toast(context, 'Recovery code is ready.'); }
  }

  Widget row(String title, IconData icon, VoidCallback action, {String? subtitle}) => ListTile(
    leading: Icon(icon), title: Text(tr(context,title)), subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right), onTap: action);
  void page(String name) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(section: name)));
  Widget group(List<Widget> children) => VaultCard(child: Column(children: children));
  Widget picker<T>(String label, T value, Map<T,String> options, void Function(T) change) => Padding(
    padding: const EdgeInsets.all(16), child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'), initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (v) { if (v != null) change(v); }));

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(vaultProvider);
    return ListenableBuilder(listenable: c, builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(tr(context,widget.section ?? 'Settings'))),
      body: AbsorbPointer(absorbing: busy, child: Align(alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: ListView(
          padding: const EdgeInsets.all(16), children: [
            if (busy) const LinearProgressIndicator(),
            ...content(c),
            const SizedBox(height: 24),
          ]))))));
  }
  List<Widget> content(VaultController c) {
    switch (widget.section) {
      case 'Appearance': return [
        group([
          picker('Theme', c.theme, const {'system':'System', 'light':'Light', 'dark':'Dark'}, (v) => run(() => c.setting('theme', v))),
          SwitchListTile(title: const Text('Glass cards'), subtitle: const Text('Soft blur and translucent surfaces'),
            value: c.glass, onChanged: (v) => run(() => c.setting('glass', '$v'))),
          SwitchListTile(title: const Text('Animations'), subtitle: const Text('Follows your device’s reduced motion setting'),
            value: c.motion, onChanged: (v) => run(() => c.setting('motion', '$v'))),
        ]),
        VaultCard(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accent colour', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in accentColours.entries) ChoiceChip(
                avatar: CircleAvatar(backgroundColor: e.value, radius: 9), label: Text(e.key),
                selected: c.accent == e.value.toARGB32(),
                onSelected: (_) => run(() => c.setting('accent', '${e.value.toARGB32()}'))),
            ]),
            const SizedBox(height: 12), const Text('Buttons, highlights and glass tints follow your choice.'),
          ]))),
      ];
      case 'Security': return [group([
        row(c.security.enabled ? 'Change PIN' : 'Set PIN', Icons.pin_outlined, () => run(() async {
          if (await authenticate(c) && mounted) await configurePin(context, c);
        })),
        if (c.security.enabled) ...[
          SwitchListTile(title: const Text('Biometrics first'), subtitle: const Text('PIN stays available as a fallback'),
            value: c.security.biometricEnabled, onChanged: (v) => run(() async {
              if (await authenticate(c)) { await c.security.setBiometric(v); c.refresh(); }
            })),
          row('Recovery code', Icons.key_outlined, () => run(() => recovery(c)),
            subtitle: c.security.hasRecovery ? 'Replace saved code' : 'Set up Forgot PIN recovery'),
          picker('Auto-lock', c.lockSeconds, const {0:'Immediately',30:'30 seconds',60:'1 minute',300:'5 minutes'},
            (v) => run(() => c.setting('lockSeconds', '$v'))),
          row('Turn off lock', Icons.lock_open_outlined, () => run(() async {
            if (await authenticate(c) && mounted && await confirm(context, 'Turn off lock?',
              'Anyone with access to this device can open your vault. Your recovery code will also be removed.', action: 'Turn off')) {
              await c.security.disable(); c.refresh();
            }
          })),
        ],
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          SwitchListTile(title: const Text('Block screenshots'), value: c.secureScreen,
            onChanged: (v) => run(() => c.setting('secureScreen', '$v'))),
      ])];
      case 'Reminders': return [group([
        SwitchListTile(title: const Text('Notifications'),
          subtitle: Text(c.reminders.supported ? 'Item details stay private' : 'Not supported on this platform'),
          value: c.notifications, onChanged: !c.reminders.supported ? null : (v) => run(() async {
            if (v && !await c.reminders.requestPermission()) {
              throw const FormatException('Allow Safe Vault notifications in your device settings.');
            }
            await c.setting('notifications', '$v');
          })),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          row('Precise timing', Icons.alarm, () => run(() async {
            await c.reminders.requestPreciseTiming(); await c.reconcile(); c.refresh();
          }), subtitle: 'Manage Android alarm permission'),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          row('Open notification settings', Icons.notifications_active_outlined,
            () => run(() => c.reminders.openNotificationSettings()),
            subtitle: 'Allow alerts and enable the Vault reminders channel'),
        row('View reminders', Icons.notifications_outlined, () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const ReminderCenter()))),
      ]),
      if (c.notifications && c.reminders.warning != null)
        const Padding(padding: EdgeInsets.all(12), child: Text('Some alerts may be unavailable. Check notification permissions and battery restrictions in device settings.')),
      ];
      case 'Backup': return [group([
        row('Save backup', Icons.lock_outline, () => run(() async { if (await authenticate(c)) await backup(c); })),
        row('Restore backup', Icons.restore, () => run(() => restore(c))),
        row('Export CSV', Icons.table_view_outlined, () => run(() async { if (await authenticate(c)) await export(c, false); })),
        row('Export PDF', Icons.picture_as_pdf_outlined, () => run(() async { if (await authenticate(c)) await export(c, true); })),
      ]), FutureBuilder<String?>(future: c.repo.preference('lastBackup'), builder: (_, s) => Padding(
        padding: const EdgeInsets.all(12), child: Text(s.data == null ? 'Keep a backup outside this device.' : 'Last backup: ${s.data!.split('T').first}')))];
      case 'Preferences': return [group([
        picker('Language', c.language, const {'en':'English','ta':'தமிழ் · core screens'}, (v) => run(() => c.setting('language', v))),
        const Padding(padding: EdgeInsets.all(16), child: Text('Tamil covers navigation and common controls. Detailed guides, errors and some tools remain in English.')),
        picker('Currency', c.currency, const {'INR':'INR','USD':'USD','EUR':'EUR','GBP':'GBP'}, (v) => run(() => c.setting('currency', v))),
      ])];
      case 'Guide': return [
        const VaultCard(child: Padding(padding: EdgeInsets.all(20), child: Text('Start here: 1. Set a PIN and recovery code in Security. 2. Allow reminders. 3. Add an item, then open Files to attach more documents. 4. Save an encrypted backup outside this device.'))),
        TextButton(onPressed: () => run(() => c.setting('onboarding', 'true')), child: const Text('Mark setup reviewed')),

        for (final entry in const <String,String>{
          'Your vault':'Doc stores documents, Sub tracks subscriptions, Notes holds notes, and Plan shows tasks and dated items. Use Add to create an item. Search looks across the vault.',
          'Files':'Open an item and tap its attachment to preview supported images, PDFs or text. Other formats can be saved to open in another app. Each attachment can be up to 10 MB.',
          'Reminders':'Choose a quick delay, a custom duration or an exact date and time in the editor. Allow notifications in Settings. Android precise timing needs alarm permission. iOS alerts also depend on Focus and notification settings. Past due means the reminder time passed; it does not confirm delivery.',
          'Repeat and snooze':'Mark a recurring task complete or a subscription paid to advance its next due date. Snooze moves its reminder without changing the due date.',
          'Forgot PIN':'Enable biometrics and save a recovery code in Security before you need them. Forgot PIN accepts enabled biometrics or your saved code. A code works once; generate a new one afterward. Without either method, your PIN is required. A backup can be restored after starting fresh; clearing app data loses local records.',
          'Backup and privacy':'Backups are encrypted with a separate password of at least 12 characters. Keep that password safe. Restore replaces your current records. CSV and PDF exports are readable files. Native storage encrypts records and attachments; browser storage has weaker device protection.',
          'Archive and trash':'Archive hides an item from the main list. Trash holds deleted items for 30 days. Choose Archive or Trash from Show to restore them.',
          'Widgets':'Add the Safe Vault widget through your device’s widget picker on a supported native build. Widgets open the vault and keep record details hidden. Glass cards changes the app’s appearance.',
        }.entries) VaultCard(child: ExpansionTile(title: Text(entry.key), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          expandedCrossAxisAlignment: CrossAxisAlignment.start, children: [Text(entry.value)])),
        const Padding(padding: EdgeInsets.all(12), child: Text('Safe Vault 1.3 • Local storage • No account required')),
      ];
      default: return [
        group([row('Personalize', Icons.dashboard_customize_outlined, () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => OrganizerSettings(controller: c)))),
          row('Storage', Icons.storage_outlined, () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StorageScreen(controller: c))))]),
        group([row('Appearance', Icons.palette_outlined, () => page('Appearance')),
          row('Security', Icons.shield_outlined, () => page('Security')),
          row('Reminders', Icons.notifications_outlined, () => page('Reminders'))]),
        group([row('Backup', Icons.cloud_upload_outlined, () => page('Backup')),
          row('Preferences', Icons.tune, () => page('Preferences'))]),
        group([row('Guide', Icons.menu_book_outlined, () => page('Guide'))]),
      ];
    }
  }
}
