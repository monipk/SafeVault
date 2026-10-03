import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'design.dart';
import 'package:uuid/uuid.dart';

import '../core/controller.dart';
import '../core/model.dart';
import 'common.dart';
import 'reminder_picker.dart';
import 'attachment_viewer.dart';

class ItemEditor extends StatefulWidget {
  final VaultController controller;
  final Kind kind;
  final Item? item, draft;
  final Uint8List? initialFile;
  const ItemEditor({
    super.key,
    required this.controller,
    required this.kind,
    this.item, this.draft, this.initialFile,
  });
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, body, category, tags, amount;
  late String currency, cycle, status, filename;
  DateTime? due, reminderAt;
  int reminderMinute = 540, leadDays = 0;
  bool remind = false, busy = false, removeFile = false, allowPop = false;
  late String initialDraft;
  Uint8List? file;
  @override
  void initState() {
    super.initState();
    final i = widget.item ?? widget.draft;
    title = TextEditingController(text: i?.title ?? '');
    body = TextEditingController(text: i?.body ?? '');
    category = TextEditingController(text: i?.category ?? '');
    tags = TextEditingController(text: i?.tags ?? '');
    amount = TextEditingController(
      text: i == null ? '' : (i.amount / 100).toStringAsFixed(2),
    );
    currency = i?.currency ?? widget.controller.currency;
    cycle = i?.cycle ?? (widget.kind == Kind.subscription ? 'Monthly' : 'None');
    status = i?.status ?? 'Active';
    file = widget.initialFile;
    filename = i?.attachmentName ?? '';
    due = i?.due;
    reminderAt = i?.reminderAt;
    remind = i?.remind ?? false;
    reminderMinute = i?.reminderMinute ?? 540;
    leadDays = i?.leadDays ?? 0;
    initialDraft = draft;
    for (final field in [title, body, category, tags, amount]) {
      field.addListener(changed);
    }
  }

  String get draft => [title.text, body.text, category.text, tags.text, amount.text,
    currency, cycle, status, filename, due, reminderAt, remind, removeFile].join('\u0000');
  bool get dirty => draft != initialDraft || file != null;
  void changed() { if (mounted) setState(() {}); }
  void leave([bool? saved]) {
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  @override
  void dispose() {
    for (final c in [title, body, category, tags, amount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: due ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) {
      setState(() => due = selected);
    }
  }

  Future<void> attach() async {
    await attempt(context, () async {
      final selected = await widget.controller.files.pick();
      if (selected != null && mounted) {
        if (await widget.controller.repo.duplicate(selected.bytes)) {
          if (!mounted || !await confirm(context,'Duplicate file','This file already exists in your vault. Attach another copy?',action:'Attach copy')) return;
        }
        if (!mounted) return;
        setState(() {
          file = selected.bytes;
          filename = selected.name;
          removeFile = false;
        });
      }
    });
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) {
      return;
    }
    if ((widget.kind == Kind.subscription ||
            widget.kind == Kind.task ||
            (remind && reminderAt == null)) &&
        due == null) {
      toast(context, 'Choose a due date.');
      return;
    }
    setState(() => busy = true);
    try {
      final old = widget.item;
      if (remind && reminderAt != null && reminderAt != old?.reminderAt && !reminderAt!.isAfter(DateTime.now())) {
        throw const FormatException('Choose a reminder time in the future.');
      }
      if (remind && widget.controller.reminders.supported && !widget.controller.notifications) {
        final allowed = await widget.controller.reminders.requestPermission();
        if (allowed) await widget.controller.setting('notifications', 'true');
      }
      final metadata = <String,dynamic>{...?(old ?? widget.draft)?.extra};
      if (old != null && widget.kind == Kind.subscription && old.amount != parseMoney(amount.text)) {
        metadata['prices'] = [...((metadata['prices'] as List?) ?? []),
          {'date':DateTime.now().toUtc().toIso8601String(),'from':old.amount,'to':parseMoney(amount.text),'currency':currency}].reversed.take(100).toList().reversed.toList();
      }
      final item = Item(
        extra: metadata,
        id: old?.id ?? const Uuid().v4(),
        kind: widget.kind,
        title: title.text.trim(),
        body: body.text.trim(),
        category: category.text.trim(),
        tags: tags.text.trim(),
        amount: widget.kind == Kind.subscription ? parseMoney(amount.text) : 0,
        currency: currency,
        cycle: cycle,
        status: status,
        due: due,
        anchorDay: old?.due == due && old != null
            ? old.anchorDay
            : (due?.day ?? 0),
        remind: remind,
        reminderAt: reminderAt,
        reminderMinute: reminderMinute,
        leadDays: leadDays,
        attachmentName: filename,
        favorite: old?.favorite ?? false,
        archived: old?.archived ?? false,
        done: old?.done ?? false,
      );
      await widget.controller.save(
        item,
        attachment: file,
        removeAttachment: removeFile,
      );
      if (mounted) {
        final warning = widget.controller.reminders.warning;
        if (remind && (!widget.controller.notifications || warning != null)) {
          toast(context, 'Saved. Check notification permissions in Settings → Reminders.');
        }
        leave(true);
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is FormatException
              ? e.message
              : 'Unable to save. Check available storage and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: allowPop || (!dirty && !busy),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || busy) return;
      if (await confirm(context, 'Discard changes?', 'Your changes have not been saved.', action: 'Discard') && mounted) leave();
    },
    child: Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.item == null ? 'New' : 'Edit'} ${widget.kind.singular.toLowerCase()}',
      ),
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: switch (widget.kind) {
                      Kind.document => 'e.g. Passport',
                      Kind.subscription => 'e.g. Internet plan',
                      Kind.note => 'Give your note a title',
                      Kind.task => 'e.g. Vehicle service',
                    },
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'A name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: category,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    hintText: widget.kind == Kind.task
                        ? 'Maintenance, birthday, anniversary…'
                        : 'Personal, home, work…',
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.kind == Kind.subscription) ...[
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    validator: (v) { try { parseMoney(v ?? ''); return null; }
                      catch (_) { return 'Enter a valid amount'; } },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: currency, isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: [for (final c in ['INR','USD','EUR','GBP']) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => currency = v!),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                    ),
                    items: [
                      for (final s in ['Active', 'Paused', 'Cancelled'])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => status = v!),
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.kind != Kind.note) ...[
                  OutlinedButton.icon(
                    onPressed: selectDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      due == null
                          ? (widget.kind == Kind.document
                                ? 'Expiry date'
                                : 'Due date')
                          : '${widget.kind == Kind.document ? 'Expires' : 'Due'}: ${dateKey(due!)}',
                    ),
                  ),
                  if (due != null && widget.kind == Kind.document)
                    TextButton(
                      onPressed: () => setState(() {
                        due = null;
                        remind = false;
                      }),
                      child: const Text('Clear date'),
                    ),
                  const SizedBox(height: 16),
                  if (widget.kind != Kind.document)
                    DropdownButtonFormField<String>(
                      initialValue: cycle,
                      decoration: const InputDecoration(
                        labelText: 'Repeat',
                      ),
                      items: [
                        for (final c in cycles)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => cycle = v!),
                    ),
                  const SizedBox(height: 16),
                ],
                ReminderPicker(
                  enabled: remind, selected: reminderAt,
                  onChanged: (enabled, at) => setState(() {
                    remind = enabled; reminderAt = at;
                    if (enabled && at != null && due == null && widget.kind != Kind.note) due = dayOnly(at);
                  }),
                ),
                if (remind && reminderAt == null)
                  Text('Existing schedule: $leadDays days before the due date, '
                    '${TimeOfDay(hour: reminderMinute ~/ 60, minute: reminderMinute % 60).format(context)}. Choose a new time above to replace it.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: body,
                  minLines: widget.kind == Kind.note ? 8 : 4,
                  maxLines: 16,
                  maxLength: 100000,
                  decoration: InputDecoration(
                    labelText: widget.kind == Kind.note
                        ? 'Note'
                        : 'Details',
                    alignLabelWithHint: true,
                    hintText: widget.kind == Kind.document
                        ? 'Issuer, reference number, renewal steps…'
                        : 'Add details you want to remember',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: tags,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'Separate tags with commas',
                  ),
                ),
                const SizedBox(height: 16),
                VaultCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attachment',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          filename.isEmpty
                              ? 'One file · up to 10 MB'
                              : filename,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: attach,
                              icon: const Icon(Icons.attach_file),
                              label: Text(
                                filename.isEmpty
                                    ? 'Attach'
                                    : 'Replace',
                              ),
                            ),
                            if (filename.isNotEmpty)
                              OutlinedButton.icon(icon: const Icon(Icons.visibility_outlined),
                                label: const Text('View'), onPressed: () => attempt(context, () async {
                                  final bytes = file ?? (widget.item == null ? null : await widget.controller.repo.attachment(widget.item!.id));
                                  if (bytes == null) throw const FormatException('The attachment is missing.');
                                  if (!mounted) return;
                                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AttachmentViewer(
                                    name: filename, bytes: bytes, export: () async { await widget.controller.files.save(filename, bytes); })));
                                })),
                            if (filename.isNotEmpty)
                              TextButton(
                                onPressed: () => setState(() {
                                  filename = '';
                                  file = null;
                                  removeFile = true;
                                }),
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: save,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    busy
                        ? 'Saving…'
                        : 'Save',
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
}
