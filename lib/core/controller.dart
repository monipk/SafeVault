import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup.dart';
import 'crypto.dart';
import 'database.dart';
import 'model.dart';
import 'reminders.dart';
import 'repository.dart';
import 'security.dart';

final vaultProvider = Provider<VaultController>(
  (ref) => throw UnimplementedError('Override at startup'),
);
final itemsProvider = StreamProvider<List<Item>>((ref) async* {
  final c = ref.watch(vaultProvider);
  yield await c.repo.all();
  await for (final _ in c.repo.changes.stream) {
    yield await c.repo.all();
  }
});

class VaultController extends ChangeNotifier {
  final VaultRepository repo;
  final SecurityService security;
  final ReminderService reminders;
  final files = FileService();
  late final BackupService backups = BackupService(repo);
  String theme = 'system', currency = 'INR';
  bool glass = false, motion = true;
  int accent = 0xff17645d;
  double textSize = 1.1;
  bool contrast = false, quiet = false;
  int quietStart = 1320, quietEnd = 480;
  List<int> visibleTabs = [0,1,2,3,4];
  List<String> dashboard = ['summary','spending'];
  List<String> folders = ['College','Personal','Finance'];
  bool onboarding = false;
  String language = 'en';
  bool notifications = false, secureScreen = true, locked = false;
  int lockSeconds = 30;
  Future<void> _queue = Future.value();
  Future<void> _reminderQueue = Future.value();
  VaultController(this.repo, this.security, this.reminders);
  static Future<VaultController> create() async {
    final c = VaultController(
      VaultRepository(VaultDatabase(), VaultCrypto()),
      SecurityService(),
      ReminderService(),
    );
    try {
      await c.repo.initialize();
      await c.security.initialize();
      c.theme = await c.repo.preference('theme') ?? 'system';
      c.textSize = double.tryParse(await c.repo.preference('textSize') ?? '') ?? 1.1;
      c.contrast = await c.repo.preference('contrast') == 'true';
      c.quiet = await c.repo.preference('quiet') == 'true';
      c.quietStart = int.tryParse(await c.repo.preference('quietStart') ?? '') ?? 1320;
      c.quietEnd = int.tryParse(await c.repo.preference('quietEnd') ?? '') ?? 480;
      c.onboarding = await c.repo.preference('onboarding') == 'true';
      c.language = await c.repo.preference('language') ?? 'en';
      final tabs = await c.repo.preference('visibleTabs');
      if (tabs != null) c.visibleTabs = (jsonDecode(tabs) as List).cast<int>();
      final cards = await c.repo.preference('dashboard');
      if (cards != null) c.dashboard = (jsonDecode(cards) as List).cast<String>();
      final folders = await c.repo.preference('folders');
      if (folders != null) c.folders = (jsonDecode(folders) as List).cast<String>();
      c.glass = await c.repo.preference('glass') == 'true';
      c.motion = await c.repo.preference('motion') != 'false';
      c.accent = int.tryParse(await c.repo.preference('accent') ?? '') ?? 0xff17645d;
      c.currency = await c.repo.preference('currency') ?? 'INR';
      c.notifications = await c.repo.preference('notifications') == 'true';
      c.secureScreen = await c.repo.preference('secureScreen') != 'false';
      c.lockSeconds =
          int.tryParse(await c.repo.preference('lockSeconds') ?? '30') ?? 30;
      c.locked = c.security.enabled;
      await c.reminders.initialize();
      try {
        await c.security.screenshotProtection(c.secureScreen);
      } catch (_) {
        c.reminders.warning =
            'Screenshot protection is unavailable on this device.';
      }
      await c.repo.purgeExpiredTrash();
      await c.reconcile();
      return c;
    } catch (_) {
      await c.repo.dispose();
      rethrow;
    }
  }

  Future<void> reconcile() {
    final job = _reminderQueue.then((_) async {
      await reminders.reconcile(repo, await repo.all(), notifications);
    });
    _reminderQueue = job.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return job;
  }

  Future<void> mutate(Future<void> Function() operation) {
    final job = _queue.then((_) async {
      await operation();
      await reconcile();
      notifyListeners();
    });
    _queue = job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return job;
  }

  Future<void> save(
    Item i, {
    Uint8List? attachment,
    bool removeAttachment = false,
  }) => mutate(
    () => repo.save(
      i,
      attachment: attachment,
      removeAttachment: removeAttachment,
    ),
  );
  Future<void> complete(Item i) async {
    if (i.due != null && i.cycle != 'None') {
      final next = advanceDate(
        i.due!,
        i.cycle,
        anchorDay: i.anchorDay == 0 ? i.due!.day : i.anchorDay,
      );
      await save(
        i.patch({
          'due': dateKey(next),
          'reminderAt': nextReminderFor(i, next)?.toUtc().toIso8601String(),
          'done': false,
          'extra': {...i.extra, 'alerts': i.additionalReminders.map((a) {
            final shift = DateTime.utc(next.year,next.month,next.day).difference(DateTime.utc(i.due!.year,i.due!.month,i.due!.day)).inDays;
            return DateTime(a.year,a.month,a.day+shift,a.hour,a.minute,a.second).toUtc().toIso8601String();
          }).toList()},
          'body': '${i.body}\nCompleted ${dateKey(DateTime.now())}'.trim(),
        }),
      );
    } else {
      await save(i.patch({'done': !i.done}));
    }
  }

  Future<void> setting(String key, String value) async {
    await repo.setPreference(key, value);
    switch (key) {
      case 'textSize': textSize = double.parse(value);
      case 'contrast': contrast = value == 'true';
      case 'language': language = value;
      case 'folders': folders = (jsonDecode(value) as List).cast<String>();
      case 'visibleTabs': visibleTabs = (jsonDecode(value) as List).cast<int>();
      case 'dashboard': dashboard = (jsonDecode(value) as List).cast<String>();
      case 'onboarding': onboarding = value == 'true';
      case 'quiet': quiet = value == 'true'; await reconcile();
      case 'quietStart': quietStart = int.parse(value); await reconcile();
      case 'quietEnd': quietEnd = int.parse(value); await reconcile();
      case 'glass':
        glass = value == 'true';
      case 'motion':
        motion = value == 'true';
      case 'accent':
        accent = int.parse(value);
      case 'theme':
        theme = value;
      case 'currency':
        currency = value;
      case 'notifications':
        notifications = value == 'true';
        await reconcile();
      case 'secureScreen':
        secureScreen = value == 'true';
        await security.screenshotProtection(secureScreen);
      case 'lockSeconds':
        lockSeconds = int.parse(value);
    }
    notifyListeners();
  }

  void lock() {
    if (security.enabled) {
      locked = true;
      notifyListeners();
    }
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
