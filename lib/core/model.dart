import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';

enum Kind { document, subscription, note, task }

extension KindLabel on Kind {
  String get label => switch (this) {
    Kind.document => 'Documents',
    Kind.subscription => 'Subscriptions',
    Kind.note => 'Notes',
    Kind.task => 'Planner',
  };
  String get singular => switch (this) {
    Kind.document => 'Document',
    Kind.subscription => 'Subscription',
    Kind.note => 'Note',
    Kind.task => 'Task',
  };
}

const cycles = ['None', 'Daily', 'Weekly', 'Monthly', 'Quarterly', 'Yearly'];
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime advanceDate(DateTime d, String cycle, {int? anchorDay}) {
  if (cycle == 'Daily') {
    return DateTime(d.year, d.month, d.day + 1);
  }
  if (cycle == 'Weekly') {
    return DateTime(d.year, d.month, d.day + 7);
  }
  final months = switch (cycle) {
    'Monthly' => 1,
    'Quarterly' => 3,
    'Yearly' => 12,
    _ => 0,
  };
  if (months == 0) {
    return d;
  }
  final first = DateTime(d.year, d.month + months, 1);
  return DateTime(
    first.year,
    first.month,
    min(anchorDay ?? d.day, DateTime(first.year, first.month + 1, 0).day),
  );
}

DateTime? nextReminderFor(Item item, DateTime nextDue) {
  final at = item.reminderAt;
  final due = item.due;
  if (at == null || due == null) return null;
  // Keep the calendar-day offset from due date and the chosen local clock time.
  final days = DateTime.utc(at.year, at.month, at.day)
      .difference(DateTime.utc(due.year, due.month, due.day)).inDays;
  return DateTime(nextDue.year, nextDue.month, nextDue.day + days,
      at.hour, at.minute, at.second, at.millisecond, at.microsecond);
}

int parseMoney(String value) {
  final s = value.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(s)) {
    throw const FormatException('Use an amount such as 199.00');
  }
  final p = s.split('.');
  return int.parse(p[0]) * 100 +
      int.parse(p.length == 1 ? '00' : p[1].padRight(2, '0'));
}

String money(int minor, String currency) =>
    NumberFormat.currency(name: currency, decimalDigits: 2).format(minor / 100);
int monthlyCost(Item i) => switch (i.cycle) {
  'Daily' => (i.amount * 365 / 12).round(),
  'Weekly' => (i.amount * 52 / 12).round(),
  'Quarterly' => (i.amount / 3).round(),
  'Yearly' => (i.amount / 12).round(),
  _ => i.amount,
};

class Item {
  final String id,
      title,
      body,
      category,
      tags,
      currency,
      cycle,
      status,
      attachmentName;
  final Map<String, dynamic> extra;
  String get folder => extra['folder'] as String? ?? '';
  String get searchText => extra['searchText'] as String? ?? '';
  List<DateTime> get additionalReminders => ((extra['alerts'] as List?) ?? [])
    .map((v) => DateTime.parse(v as String).toLocal()).toList();
  List<DateTime> get reminderTimes => !remind ? [] : <DateTime>{
    if (reminderTime != null) reminderTime!, ...additionalReminders}.toList()..sort();
  Item withExtra(Map<String, dynamic> values) => patch({'extra': {...extra, ...values}});
  final Kind kind;
  final int amount, reminderMinute, leadDays, anchorDay;
  final DateTime? due, deleted, reminderAt;
  final DateTime updated;
  final bool favorite, archived, done, remind;
  Item({
    this.extra = const {},
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.category = '',
    this.tags = '',
    this.currency = 'INR',
    this.cycle = 'None',
    this.status = 'Active',
    this.attachmentName = '',
    this.amount = 0,
    this.reminderMinute = 540,
    this.leadDays = 0,
    this.anchorDay = 0,
    this.due,
    this.reminderAt,
    this.deleted,
    DateTime? updated,
    this.favorite = false,
    this.archived = false,
    this.done = false,
    this.remind = false,
  }) : updated = updated ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'extra': extra,
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'category': category,
    'tags': tags,
    'currency': currency,
    'cycle': cycle,
    'status': status,
    'attachmentName': attachmentName,
    'amount': amount,
    'reminderMinute': reminderMinute,
    'leadDays': leadDays,
    'anchorDay': anchorDay,
    'reminderAt': reminderAt?.toUtc().toIso8601String(),
    'due': due == null ? null : dateKey(due!),
    'deleted': deleted?.toIso8601String(),
    'updated': updated.toIso8601String(),
    'favorite': favorite,
    'archived': archived,
    'done': done,
    'remind': remind,
  };
  factory Item.fromJson(Map<String, dynamic> j) {
    if (j['due'] != null) {
      final raw = j['due'];
      if (raw is! String ||
          DateTime.tryParse(raw) == null ||
          dateKey(DateTime.parse(raw)) != raw) {
        throw const FormatException('Invalid calendar date');
      }
    }

    final metadata = Map<String, dynamic>.from((j['extra'] as Map?) ?? {});
    if (jsonEncode(metadata).length > 200000 || ((metadata['alerts'] as List?)?.length ?? 0) > 8) {
      throw const FormatException('Item details are too large');
    }
    for (final value in (metadata['alerts'] as List?) ?? []) {
      if (value is! String || DateTime.tryParse(value) == null) throw const FormatException('Invalid reminder');
    }
    for (final key in ['folder','contact','searchText']) {
      if (metadata[key] != null && metadata[key] is! String) throw const FormatException('Invalid item text');
    }
    for (final key in ['trialEnd','cancelBy','purchased','warrantyEnd']) {
      final value=metadata[key];
      if (value != null && (value is! String || DateTime.tryParse(value)==null || dateKey(DateTime.parse(value))!=value)) {
        throw const FormatException('Invalid tracked date');
      }
    }
    if (metadata['cancelledConfirmed'] != null && metadata['cancelledConfirmed'] is! bool) throw const FormatException('Invalid cancellation status');
    final checklist=(metadata['checklist'] as List?) ?? [];
    if (checklist.length>50) throw const FormatException('Too many checklist steps');
    for (final step in checklist) {
      if (step is! Map || step['text'] is! String || step['done'] is! bool) throw const FormatException('Invalid checklist');
    }
    final prices=(metadata['prices'] as List?) ?? [];
    if (prices.length>100) throw const FormatException('Too much price history');
    for (final entry in prices) {
      if (entry is! Map || entry['from'] is! int || entry['to'] is! int || entry['currency'] is! String ||
        entry['date'] is! String || DateTime.tryParse(entry['date'] as String)==null) throw const FormatException('Invalid price history');
    }
    final i = Item(
      extra: metadata,
      id: j['id'] as String,
      kind: Kind.values.byName(j['kind'] as String),
      title: j['title'] as String,
      body: j['body'] as String,
      category: j['category'] as String,
      tags: j['tags'] as String,
      currency: j['currency'] as String,
      cycle: j['cycle'] as String,
      status: j['status'] as String,
      attachmentName: j['attachmentName'] as String,
      amount: j['amount'] as int,
      reminderMinute: j['reminderMinute'] as int,
      leadDays: j['leadDays'] as int,
      anchorDay: j['anchorDay'] as int,
      reminderAt: j['reminderAt'] == null ? null : DateTime.parse(j['reminderAt'] as String).toLocal(),
      due: j['due'] == null ? null : DateTime.parse(j['due'] as String),
      deleted: j['deleted'] == null
          ? null
          : DateTime.parse(j['deleted'] as String),
      updated: DateTime.parse(j['updated'] as String),
      favorite: j['favorite'] as bool,
      archived: j['archived'] as bool,
      done: j['done'] as bool,
      remind: j['remind'] as bool,
    );
    if (i.id.isEmpty ||
        i.title.trim().isEmpty ||
        i.title.length > 160 ||
        i.body.length > 100000 ||
        i.amount < 0 ||
        i.amount > 999999999999 ||
        !cycles.contains(i.cycle) ||
        !['Active', 'Paused', 'Cancelled'].contains(i.status) ||
        !['INR', 'USD', 'EUR', 'GBP'].contains(i.currency) ||
        i.reminderMinute < 0 ||
        i.reminderMinute > 1439 ||
        i.leadDays < 0 ||
        i.leadDays > 365 ||
        i.anchorDay < 0 ||
        i.anchorDay > 31) {
      throw const FormatException('Invalid record in backup');
    }
    return i;
  }
  Item patch(Map<String, dynamic> changes) => Item.fromJson({
    ...toJson(),
    ...changes,
    'updated': DateTime.now().toIso8601String(),
  });
  bool get active =>
      deleted == null && !archived && !done && status == 'Active';
  DateTime? get reminderTime {
    if (!remind) return null;
    if (reminderAt != null) return reminderAt;
    final d = due;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day - leadDays,
        reminderMinute ~/ 60, reminderMinute % 60);
  }
  String get searchable => '$title $body $category $tags $folder $searchText'.toLowerCase();
  String get dateLabel =>
      due == null ? 'No date' : DateFormat.yMMMd().format(due!);
  String get urgency {
    if (due == null || !active) {
      return '';
    }
    final days = DateTime.utc(due!.year, due!.month, due!.day)
        .difference(
          DateTime.utc(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        )
        .inDays;
    if (days < 0) {
      return kind == Kind.document ? 'Expired' : 'Overdue';
    }
    if (days == 0) {
      return 'Today';
    }
    if (days <= 7) {
      return 'Due soon';
    }
    return '';
  }
}

String encodeItem(Item i) => jsonEncode(i.toJson());
