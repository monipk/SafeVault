import 'package:flutter/material.dart';
import 'design.dart';
import 'item_tools.dart';
import '../core/calendar_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model.dart';
import '../core/controller.dart';
import 'common.dart';
import 'editor.dart';
import 'attachment_viewer.dart';

class ItemDetail extends ConsumerWidget {
  final String id;
  const ItemDetail({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(vaultProvider);
    final data = ref.watch(itemsProvider);
    return data.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          title: 'Could not load this item',
          subtitle: 'Go back and try again.',
        ),
      ),
      data: (items) {
        final matches = items.where((i) => i.id == id);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              title: 'Item removed',
              subtitle: 'This item is no longer in your vault.',
            ),
          );
        }
        final item = matches.first;
        Future<void> update(Map<String, dynamic> changes) =>
            attempt(context, () => c.save(item.patch(changes)));
        return Scaffold(
          appBar: AppBar(
            title: Text(item.kind.singular),
            actions: [
              IconButton(
                tooltip: item.favorite ? 'Remove favorite' : 'Add favorite',
                onPressed: () => update({'favorite': !item.favorite}),
                icon: Icon(
                  item.favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                ),
              ),
              if (item.deleted == null)
                IconButton(
                  tooltip: 'Edit item',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (_) => ItemEditor(
                        controller: c,
                        kind: item.kind,
                        item: item,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Icon(
                    kindIcon(item.kind),
                    size: 44,
                    color: kindColor(item.kind),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (item.category.isNotEmpty)
                        Chip(label: Text(item.category)),
                      if (item.urgency.isNotEmpty)
                        Chip(label: Text(item.urgency)),
                      if (item.archived) const Chip(label: Text('Archived')),
                      if (item.done) const Chip(label: Text('Completed')),
                      for (final t
                          in item.tags
                              .split(',')
                              .where((s) => s.trim().isNotEmpty))
                        Chip(label: Text(t.trim())),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (item.kind == Kind.subscription)
                    VaultCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              money(item.amount, item.currency),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text('${item.cycle} · ${item.status}'),
                            const SizedBox(height: 10),
                            Text(
                              'Monthly equivalent: ${money(monthlyCost(item), item.currency)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (item.due != null)
                    VaultCard(
                      child: ListTile(
                        leading: const Icon(Icons.event_outlined),
                        title: Text(item.dateLabel),
                        subtitle: Text(
                          '${item.kind == Kind.document ? 'Expiry date' : 'Next due date'}${item.cycle != 'None' ? ' · ${item.cycle}' : ''}',
                        ),
                      ),
                    ),
                  if (item.remind)
                    VaultCard(
                      child: ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: Text(
                          item.reminderAt != null ? item.reminderAt!.toLocal().toString().split('.').first :
                          '${item.leadDays == 0 ? 'Same day' : '${item.leadDays} days before'} at ${TimeOfDay(hour: item.reminderMinute ~/ 60, minute: item.reminderMinute % 60).format(context)}',
                        ),
                        subtitle: Text(
                          c.notifications
                              ? 'Reminder enabled; system permissions apply'
                              : 'Enable notifications in Settings',
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    item.kind == Kind.note ? 'NOTE' : 'DETAILS',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    item.body.isEmpty ? 'No additional details.' : item.body,
                    style: const TextStyle(fontSize: 16, height: 1.65),
                  ),
                  const SizedBox(height: 24),
                  VaultCard(child: Column(children: [
                    ListTile(leading: const Icon(Icons.folder_open), title: const Text('Files & versions'),
                      trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => FileManager(controller: c, owner: item.id)))),
                    ListTile(leading: const Icon(Icons.tune), title: const Text('Organize & reminders'),
                      subtitle: item.folder.isEmpty ? null : Text(item.folder), trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ItemOptions(controller: c, item: item)))),
                    if (item.due != null) ListTile(leading: const Icon(Icons.calendar_month), title: const Text('Export to calendar'),
                      onTap: () => attempt(context, () async {
                        if (await confirm(context, 'Export calendar event?', 'The calendar file includes the item title and due date without vault encryption.', action: 'Export')) {
                          await c.files.save('safe-vault-event.ics', calendarExport(item), mime: 'text/calendar');
                        }
                      })),
                  ])),
                  if ((item.extra['checklist'] as List?)?.isNotEmpty ?? false)
                    VaultCard(child: Column(children: [
                      for (var n = 0; n < (item.extra['checklist'] as List).length; n++)
                        CheckboxListTile(title: Text(item.extra['checklist'][n]['text'] as String),
                          value: item.extra['checklist'][n]['done'] == true, onChanged: (value) => attempt(context, () async {
                            final latest = await currentItem(c, item.id);
                            final steps = [for (final step in (latest.extra['checklist'] as List)) Map<String,dynamic>.from(step as Map)];
                            if (n < steps.length) { steps[n]['done'] = value; await c.save(latest.withExtra({'checklist': steps})); }
                          })),
                    ])),
                  if (item.attachmentName.isNotEmpty)
                    VaultCard(
                      child: ListTile(
                        leading: const Icon(Icons.attachment),
                        title: Text(item.attachmentName),
                        subtitle: const Text('View attachment'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => attempt(context, () async {
                          final bytes = await c.repo.attachment(item.id);
                          if (bytes == null) {
                            throw const FormatException(
                              'The attachment is missing.',
                            );
                          }
                          if (!context.mounted) {
                            return;
                          }
                          await Navigator.push(context, MaterialPageRoute<void>(
                            builder: (_) => AttachmentViewer(name: item.attachmentName,
                              bytes: bytes, export: () async {
                                await c.files.save(item.attachmentName, bytes);
                              })));

                        }),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (item.deleted == null) ...[
                    if (item.kind == Kind.task ||
                        item.kind == Kind.subscription)
                      FilledButton.icon(
                        onPressed: () =>
                            attempt(context, () => c.complete(item)),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          item.cycle != 'None'
                              ? '${item.kind == Kind.subscription ? 'Paid' : 'Done'} · next cycle'
                              : item.done
                              ? 'Undo completion'
                              : 'Done',
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => update({'archived': !item.archived}),
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(item.archived ? 'Unarchive' : 'Archive'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        if (!await confirm(
                          context,
                          'Move to trash?',
                          'You can restore this item for 30 days.',
                          action: 'Trash',
                        )) {
                          return;
                        }
                        if (context.mounted) {
                          await attempt(context, () async {
                            await c.save(
                              item.patch({
                                'deleted': DateTime.now().toIso8601String(),
                              }),
                            );
                            if (context.mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              messenger.clearSnackBars();
                              messenger.removeCurrentSnackBar();
                              messenger.showSnackBar(SnackBar(
                                content: const Text('Moved to trash'),
                                persist: false,
                                duration: const Duration(seconds: 3),
                                showCloseIcon: true,
                                action: SnackBarAction(label: 'Undo', onPressed: () async {
                                  try { await c.save(item.patch({'deleted': null})); }
                                  catch (_) { messenger.showSnackBar(const SnackBar(content: Text('Could not restore. Open Trash to retry.'))); }
                                })));
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Trash'),
                    ),
                  ] else ...[
                    FilledButton(
                      onPressed: () => update({'deleted': null}),
                      child: const Text('Restore'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'Delete permanently?',
                          'This item and its attachment cannot be recovered.',
                          action: 'Delete forever',
                        )) {
                          if (context.mounted) {
                            await attempt(context, () async {
                              await c.mutate(() => c.repo.purge(item.id));
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            });
                          }
                        }
                      },
                      child: const Text('Delete permanently'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Updated ${item.updated.toLocal().toString().split('.').first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
