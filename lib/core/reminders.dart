import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'model.dart';
import 'repository.dart';
import 'reminder_rules.dart';

class ReminderService {
  final plugin = FlutterLocalNotificationsPlugin();
  final openRequests = ValueNotifier<int>(0);
  final Map<int, String> _scheduled = {};
  String? warning;
  bool initialized = false, exact = false;
  int pendingCount = 0;
  bool get supported => !kIsWeb && [TargetPlatform.android,
    TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows]
    .contains(defaultTargetPlatform);
  AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> initialize() async {
    if (!supported) {
      warning = 'Background reminders are supported on Android, iOS, macOS and Windows. Use the reminder center on this platform.';
      return;
    }
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      final darwin = DarwinInitializationSettings(
        requestAlertPermission: false, requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [DarwinNotificationCategory('vault', actions: [
          DarwinNotificationAction.plain('open', 'View reminders',
            options: {DarwinNotificationActionOption.foreground}),
        ])],
      );
      await plugin.initialize(settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_vault'),
        iOS: darwin, macOS: darwin,
        windows: const WindowsInitializationSettings(appName: 'Safe Vault',
          appUserModelId: 'app.safevault.safe_vault',
          guid: 'e3f7eecb-6e93-4c50-b1db-264a990fe5b3'),
      ), onDidReceiveNotificationResponse: (_) => openRequests.value++);
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'vault_reminders_v2', 'Vault reminders',
        description: 'Private document, payment and planner alerts',
        importance: Importance.high,
      ));
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) openRequests.value++;
      initialized = true;
      warning = null;
    } catch (e) {
      warning = 'Notification setup failed: $e';
    }
  }
  Future<bool> requestPermission() async {
    if (!initialized) await initialize();
    if (!initialized) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await android?.requestNotificationsPermission();
        return await android?.areNotificationsEnabled() == true;
      case TargetPlatform.iOS:
        return await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      case TargetPlatform.macOS:
        return await plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      case TargetPlatform.windows: return true;
      default: return false;
    }
  }
  Future<void> openNotificationSettings() async {
    if (!initialized) await initialize();
    if (initialized && defaultTargetPlatform == TargetPlatform.android) {
      await android?.openAppNotificationSettings();
    }
  }
  Future<void> requestPreciseTiming() async {
    if (!initialized) await initialize();
    if (initialized && defaultTargetPlatform == TargetPlatform.android) {
      await android?.requestExactAlarmsPermission();
    }
  }
  static const details = NotificationDetails(
    android: AndroidNotificationDetails('vault_reminders_v2', 'Vault reminders',
      channelDescription: 'Private document, payment and planner alerts',
      importance: Importance.high, priority: Priority.high,
      visibility: NotificationVisibility.private, groupKey: 'safe_vault.reminders',
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(
        'An item needs your attention. Unlock Safe Vault to view it or snooze its reminder.'),
      actions: [AndroidNotificationAction('open', 'View reminders', showsUserInterface: true)],
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true,
      presentBanner: true, presentList: true, categoryIdentifier: 'vault', threadIdentifier: 'safe_vault'),
    windows: WindowsNotificationDetails(),
    macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, categoryIdentifier: 'vault'),
  );
  Future<void> cancelAll() async {
    if (initialized) await plugin.cancelAll();
    _scheduled.clear(); pendingCount = 0;
  }
  Future<void> reconcile(VaultRepository repo, List<Item> items, bool enabled) async {
    if (!initialized) return;
    try {
      if (!enabled) { await cancelAll(); warning = null; return; }
      String? permissionWarning;
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (await android?.areNotificationsEnabled() != true) {
          permissionWarning = 'Notifications are blocked. Allow Safe Vault notifications in device settings.';
        }
        exact = await android?.canScheduleExactNotifications() ?? false;
      }
      NotificationsEnabledOptions? applePermissions;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        applePermissions = await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.checkPermissions();
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        applePermissions = await plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.checkPermissions();
      }
      if (applePermissions != null && !applePermissions.isEnabled) {
        permissionWarning = 'Notifications are blocked. Enable Safe Vault alerts in system settings.';
      }
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      final ids = await repo.notificationIds();
      final now = DateTime.now();
      final quiet = await repo.preference('quiet') == 'true';
      final start = int.tryParse(await repo.preference('quietStart') ?? '') ?? 1320;
      final end = int.tryParse(await repo.preference('quietEnd') ?? '') ?? 480;
      final candidates = <({Item item, DateTime at, int id})>[];
      for (final item in items.where((i) => i.active && i.remind)) {
        final times = item.reminderTimes;
        final base = ids[item.id]!;
        if (base > 134000000) throw const FormatException('Notification identifier limit reached');
        for (var slot = 0; slot < times.length; slot++) {
          final at = quiet ? outsideQuietHours(times[slot], start, end) : times[slot];
          if (at.isAfter(now)) candidates.add((item: item, at: at, id: base*16+slot));
        }
      }
      candidates.sort((a,b) => a.at.compareTo(b.at));
      final nearest = candidates.take(60).toList();
      final wanted = nearest.map((event) => event.id).toSet();
      final pending = await plugin.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();
      for (final p in pending) {
        if (!wanted.contains(p.id)) { await plugin.cancel(id: p.id); _scheduled.remove(p.id); }
      }
      final errors = <String>[];
      for (final event in nearest) {
        final item = event.item;
        final id = event.id;
        final signature = '${item.id}:${event.at.toUtc().toIso8601String()}:$exact';
        if (_scheduled[id] == signature && pendingIds.contains(id)) continue;
        try {
          await plugin.zonedSchedule(id: id, title: 'Safe Vault reminder',
            body: 'An item needs your attention. Open your vault to view it.',
            scheduledDate: tz.TZDateTime.from(event.at, tz.local),
            notificationDetails: details, payload: item.id,
            androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle);
          _scheduled[id] = signature;
        } catch (e) { errors.add('$e'); }
      }
      pendingCount = (await plugin.pendingNotificationRequests()).length;
      warning = permissionWarning ?? (errors.isNotEmpty ? '${errors.length} reminder(s) could not be scheduled: ${errors.first}'
        : defaultTargetPlatform == TargetPlatform.android && !exact
          ? 'Precise timing is off. Android may delay alerts. Enable it in Reminder center.'
          : candidates.length > 60 ? 'The nearest 60 reminders are scheduled. Open the app to refresh the remaining reminders.' : null);
    } catch (e) { warning = 'Could not update reminder schedules: $e'; }
  }
}
