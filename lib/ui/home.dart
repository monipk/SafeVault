import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/model.dart';
import 'common.dart';
import 'design.dart';
import 'detail.dart';
import 'editor.dart';
import 'settings.dart';
import 'reminder_center.dart';
import 'tools_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends ConsumerState<HomeScreen> {
  int tab = 0, limit = 60;
  String query = '', filter = 'All', sort = 'Recent', folder = '';
  final selected = <String>{};
  DateTime? calendarDay;
  Timer? delay;
  final search = TextEditingController();
  static const labels = ['Home', 'Doc', 'Sub', 'Notes', 'Plan'];
  static const titles = ['Your vault', 'Documents', 'Subscriptions', 'Notes', 'Planner'];
  static const icons = [Icons.dashboard_outlined, Icons.folder_outlined,
    Icons.credit_card_outlined, Icons.description_outlined, Icons.event_outlined];
  @override
  void dispose() { delay?.cancel(); search.dispose(); super.dispose(); }
  void select(int value) {
    delay?.cancel();
    setState(() { selected.clear(); tab = value; calendarDay = null; query = ''; search.clear(); filter = 'All'; limit = 60; });
  }
  void open(Item item) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => ItemDetail(id: item.id)));
  Future<void> add() async {
    final c = ref.read(vaultProvider);
    final kind = tab > 0 ? Kind.values[tab - 1] : await showModalBottomSheet<Kind>(
      context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final k in Kind.values) ListTile(leading: Icon(kindIcon(k)), title: Text(k.singular),
          trailing: const Icon(Icons.add), onTap: () => Navigator.pop(context, k)),
        const SizedBox(height: 12),
      ])));
    if (kind != null && mounted) {
      await Navigator.push(context, MaterialPageRoute<bool>(
        builder: (_) => ItemEditor(controller: c, kind: kind)));
    }
  }
  Future<void> bulk(String action) async {
    final c = ref.read(vaultProvider);
    String? destination;
    if (action == 'folder') {
      destination = await showModalBottomSheet<String>(context: context, showDragHandle: true,
        builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
          for (final f in ['', ...c.folders]) ListTile(title: Text(f.isEmpty ? 'No folder' : f), onTap: () => Navigator.pop(ctx, f)),
        ])));
      if (destination == null) return;
    }
    if (action == 'trash' && (!mounted || !await confirm(context, 'Trash selected items?', 'You can restore these records for 30 days.', action: 'Trash'))) return;
    final ids = selected.toSet();
    if (!mounted) return;
    await attempt(context, () => c.mutate(() async {
      final items = (await c.repo.all()).where((i) => ids.contains(i.id));
      for (final i in items) {
        await c.repo.save(action == 'folder' ? i.withExtra({'folder': destination})
          : i.patch(action == 'archive' ? {'archived': true} : {'deleted': DateTime.now().toIso8601String()}));
      }
    }));
    if (mounted) setState(() => selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(vaultProvider);
    final data = ref.watch(itemsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(listenable: c, builder: (context, _) {
      final tabs = c.visibleTabs;
      if (!tabs.contains(tab)) tab = 0;
      return Scaffold(
      appBar: AppBar(title: Text(selected.isEmpty ? 'Safe Vault' : '${selected.length} selected'), actions: [
        if (selected.isNotEmpty) ...[
          IconButton(tooltip: 'Cancel selection', onPressed: () => setState(() => selected.clear()), icon: const Icon(Icons.close)),
          PopupMenuButton<String>(tooltip: 'Selected items', onSelected: bulk, itemBuilder: (_) => const [
            PopupMenuItem(value: 'folder', child: Text('Move to folder')), PopupMenuItem(value: 'archive', child: Text('Archive')),
            PopupMenuItem(value: 'trash', child: Text('Trash'))]),
        ] else ...[
        IconButton(tooltip: 'Reminders', icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ReminderCenter()))),
        IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: () => Navigator.push(
          context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))),
        PopupMenuButton<String>(tooltip: 'More',
          onSelected: (v) { if (v == 'lock') c.lock(); else Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ToolsScreen(controller: c))); },
          itemBuilder: (_) => [const PopupMenuItem(value: 'tools', child: Text('Tools & templates')),
            if (c.security.enabled) const PopupMenuItem(value: 'lock', child: Text('Lock vault'))]),
      ]]),
      body: Row(children: [
        if (wide) NavigationRail(selectedIndex: tabs.indexOf(tab), onDestinationSelected: (n) => select(tabs[n]),
          labelType: NavigationRailLabelType.all, destinations: [for (final i in tabs)
            NavigationRailDestination(icon: Icon(icons[i]), label: Text(tr(context,labels[i])))]),
        Expanded(child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(itemsProvider),
            child: const Text('Could not load vault. Retry'))),
          data: (items) {
            final global = query.trim().isNotEmpty;
            final shown = items.where((i) {
              if (filter == 'Trash') { if (i.deleted == null) return false; }
              else {
                if (i.deleted != null) return false;
                if (filter == 'Archive' ? !i.archived : i.archived) return false;
              }
              if (!global && tab > 0 && tab != 4 && i.kind != Kind.values[tab - 1]) return false;
              if (!global && tab == 4 && i.kind != Kind.task && i.due == null) return false;
              if (!global && tab == 4 && calendarDay != null && (i.due == null || dateKey(i.due!) != dateKey(calendarDay!))) return false;
              if (folder.isNotEmpty && i.folder != folder) return false;
              if (filter == 'Expiring' && (i.kind != Kind.document || !i.active || i.due == null || i.due!.isAfter(DateTime.now().add(const Duration(days:30))))) return false;
              if (filter == 'Favorites' && !i.favorite) return false;
              if (filter == 'Upcoming' && (i.due == null || !i.active)) return false;
              if (filter == 'Completed' && !i.done) return false;
              return !global || i.searchable.contains(query.trim().toLowerCase());
            }).toList();
            if (sort == 'Name') shown.sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
            if (sort == 'Due' || (sort == 'Recent' && (tab == 4 || filter == 'Upcoming'))) {
              shown.sort((a,b) => (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999)));
            }
            final order = {for (var n = 0; n < shown.length; n++) shown[n].id: n};
            shown.sort((a,b) => a.favorite == b.favorite ? order[a.id]!.compareTo(order[b.id]!) : a.favorite ? -1 : 1);
            final active = items.where((i) => i.deleted == null && !i.archived).toList();
            return Align(alignment: Alignment.topCenter, child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760), child: AnimatedSwitcher(
                duration: motionDuration(context), child: CustomScrollView(
                  key: ValueKey(tab), slivers: [
                    SliverPadding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Expanded(child: Text(tr(context,titles[tab]),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 12), FilledButton.icon(onPressed: add,
                            icon: const Icon(Icons.add, size: 20), label: Text(tr(context,'Add')))]),
                        const SizedBox(height: 20),
                        TextField(controller: search, onChanged: (v) {
                          delay?.cancel(); delay = Timer(const Duration(milliseconds: 250), () {
                            if (mounted) setState(() { query = v; limit = 60; });
                          });
                        }, decoration: InputDecoration(hintText: tr(context,'Search vault'), prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty ? null : IconButton(tooltip: 'Clear search',
                            icon: const Icon(Icons.close), onPressed: () {
                              delay?.cancel(); search.clear(); setState(() => query = '');
                            }))),
                        const SizedBox(height: 16),
                        if (tab == 0 && !global && filter == 'All') ...[
                          if (!c.onboarding) VaultCard(child: ListTile(leading: const Icon(Icons.shield_outlined),
                            title: const Text('Set up your vault'), subtitle: const Text('Security · reminders · backup'),
                            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
                              MaterialPageRoute<void>(builder: (_) => const SettingsScreen(section: 'Guide'))))),
                          FutureBuilder<String?>(future: c.repo.preference('lastBackup'), builder: (_, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done) return const SizedBox.shrink();
                            final at = DateTime.tryParse(snapshot.data ?? '');
                            if (active.isEmpty || (at != null && DateTime.now().difference(at).inDays < 7)) return const SizedBox.shrink();
                            return VaultCard(child: ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Time for a backup'),
                              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen(section: 'Backup')))));
                          }),
                          for (final card in c.dashboard)
                            if (card == 'spending') ...spending(active)
                            else VaultCard(child: SizedBox(width: double.infinity, child: Padding(padding: const EdgeInsets.all(20), child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${active.length} saved', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8), Text('${active.where((i) => i.urgency.isNotEmpty).length} need attention'),
                                const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final k in Kind.values.where((k) => tabs.contains(k.index+1))) ActionChip(avatar: Icon(kindIcon(k), size: 20),
                                    label: Text('${labels[k.index+1]} ${active.where((i) => i.kind == k).length}'),
                                    onPressed: () { if (tabs.contains(k.index+1)) select(k.index+1); else setState(() { query = k.singular.toLowerCase(); search.text=query; }); }),
                                ]),
                              ])))),
                        ],
                        Row(children: [Expanded(child: DropdownButtonFormField<String>(
                          initialValue: filter, key: ValueKey('filter-$tab-$filter'), isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Show', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          items: [for (final f in ['All','Favorites','Upcoming','Expiring','Completed','Archive','Trash'])
                            DropdownMenuItem(value: f, child: Text(tr(context,f), overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => setState(() { filter = v!; limit = 60; }))),
                          const SizedBox(width: 12),
                          if (tab == 4) IconButton(tooltip: 'Filter by date', icon: const Icon(Icons.calendar_month_outlined),
                            onPressed: () async {
                              final date = await showDatePicker(context: context, initialDate: calendarDay ?? DateTime.now(),
                                firstDate: DateTime(1900), lastDate: DateTime(2200));
                              if (date != null && mounted) setState(() => calendarDay = date);
                            }),
                          PopupMenuButton<String>(tooltip: 'Sort', icon: const Icon(Icons.sort),
                            initialValue: sort, onSelected: (v) => setState(() => sort = v), itemBuilder: (_) => [
                              for (final s in ['Recent','Name','Due']) PopupMenuItem(value: s, child: Text(s))]),
                        ]),
                        const SizedBox(height: 12),
                        PopupMenuButton<String>(tooltip: 'Folder filter', onSelected: (v) => setState(() => folder = v),
                          itemBuilder: (_) => [for (final f in <String>{'',...c.folders,...items.map((i) => i.folder)})
                            PopupMenuItem(value: f, child: Text(f.isEmpty ? 'All folders' : f))],
                          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisSize: MainAxisSize.min,
                            children: [const Icon(Icons.folder_outlined), const SizedBox(width: 8), Flexible(child: Text(folder.isEmpty ? tr(context,'All folders') : folder, maxLines: 1, overflow: TextOverflow.ellipsis)), const Icon(Icons.expand_more)]))),
                        if (tab == 4 && calendarDay != null && !global) InputChip(label: Text(dateKey(calendarDay!)),
                          onDeleted: () => setState(() => calendarDay = null)),
                        Text('${shown.length} ${global ? 'results' : 'items'}', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 12),
                      ]))),
                    if (shown.isEmpty) SliverFillRemaining(hasScrollBody: false, child: Align(
                      alignment: const Alignment(0,-.15), child: EmptyState(title: global ? 'No matches' : 'Nothing here yet',
                          subtitle: global ? 'Try another search.' : filter == 'Trash' ? 'Deleted items stay for 30 days.' : 'Use Add to save an item.', icon: icons[tab]))),
                    SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverList.builder(
                      itemCount: shown.length < limit ? shown.length : limit,
                      itemBuilder: (_, index) => Row(children: [
                        if (selected.isNotEmpty) Checkbox(value: selected.contains(shown[index].id), onChanged: (_) => setState(() {
                          selected.contains(shown[index].id) ? selected.remove(shown[index].id) : selected.add(shown[index].id);
                        })),
                        Expanded(child: ItemTile(item: shown[index], onTap: () {
                          if (selected.isEmpty) open(shown[index]); else setState(() {
                            selected.contains(shown[index].id) ? selected.remove(shown[index].id) : selected.add(shown[index].id);
                          });
                        }, onLongPress: () => setState(() => selected.add(shown[index].id)))),
                      ]))),
                    if (shown.length > limit) SliverToBoxAdapter(child: TextButton(
                      onPressed: () => setState(() => limit += 60), child: const Text('Load more'))),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ]))));
          })),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: tabs.indexOf(tab), onDestinationSelected: (n) => select(tabs[n]),
        destinations: [for (final i in tabs)
          NavigationDestination(icon: Icon(icons[i]), label: tr(context,labels[i]))]),
    ); });
  }
  List<Widget> spending(List<Item> items) {
    final totals = <String,int>{};
    for (final i in items.where((i) => i.kind == Kind.subscription && i.active)) {
      totals.update(i.currency, (v) => v + monthlyCost(i), ifAbsent: () => monthlyCost(i));
    }
    if (totals.isEmpty) return [];
    return [VaultCard(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Monthly estimate', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6), for (final e in totals.entries)
          Text('${money(e.value, e.key)} / month\n${money(e.value*12, e.key)} / year', style: Theme.of(context).textTheme.titleMedium),
      ])))];
  }
}
