import 'package:flutter/material.dart';
import 'design.dart';

import '../core/model.dart';

IconData kindIcon(Kind kind) => switch (kind) {
  Kind.document => Icons.folder_outlined,
  Kind.subscription => Icons.credit_card_outlined,
  Kind.note => Icons.description_outlined,
  Kind.task => Icons.event_outlined,
};
Color kindColor(Kind kind) => switch (kind) {
  Kind.document => const Color(0xff17645D),
  Kind.subscription => const Color(0xff5B57A2),
  Kind.note => const Color(0xff996325),
  Kind.task => const Color(0xff35688B),
};
void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      toast(
        context,
        e is FormatException
            ? e.message
            : 'Could not complete this action. Check storage or permissions and try again.',
      );
    }
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? add;
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.inventory_2_outlined,
    this.add,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: SizedBox(width: double.infinity, child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr(context,title),
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          tr(context,subtitle),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (add != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ],
    )),
  );
}

class ItemTile extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const ItemTile({super.key, required this.item, required this.onTap, this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final c = kindColor(item.kind);
    return VaultCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(kindIcon(item.kind), color: c),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            [
              if (item.kind == Kind.subscription)
                '${money(item.amount, item.currency)} · ${item.cycle}',
              if (item.folder.isNotEmpty) item.folder,
              if (item.category.isNotEmpty) item.category,
              if (item.due != null) item.dateLabel,
              if (item.kind == Kind.note && item.body.isNotEmpty)
                item.body.replaceAll('\n', ' '),
              if (item.done) 'Completed',
              if (item.status != 'Active') item.status,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.favorite)
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: Color(0xffA56D12),
              ),
            if (item.urgency.isNotEmpty)
              Text(
                item.urgency,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: item.urgency == 'Overdue' || item.urgency == 'Expired'
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              )
            else
              const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
