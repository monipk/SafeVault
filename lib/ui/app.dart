import 'dart:async';

import 'package:flutter/material.dart';

import '../core/controller.dart';
import 'home.dart';
import 'design.dart';
import 'lock.dart';
import 'reminder_center.dart';

const ink = Color(0xff112D32);
const teal = Color(0xff17645D);
ThemeData vaultTheme(Brightness brightness, {Color accent = teal, bool glass = false, bool motion = true, bool contrast = false, String language = 'en'}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness, contrastLevel: contrast ? 1 : 0);
  return ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48,48))),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 16),
    extensions: [VaultStyle(glass: glass, motion: motion, language: language)],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: VaultPageTransitions(), TargetPlatform.iOS: VaultPageTransitions(),
      TargetPlatform.macOS: VaultPageTransitions(), TargetPlatform.windows: VaultPageTransitions(),
      TargetPlatform.linux: VaultPageTransitions(),
    }),
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff101B1D)
        : const Color(0xffF5F5F0),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff101B1D) : const Color(0xffF5F5F0),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xff1B2B2D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: dark ? const Color(0xff304144) : const Color(0xffE4E8E3),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff223436) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xffDCE3DD)),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52)),
    ),
    navigationBarTheme: const NavigationBarThemeData(height: 80, labelBehavior: NavigationDestinationLabelBehavior.alwaysShow),
    dividerTheme: const DividerThemeData(space: 1),
  );
}

class SafeVaultApp extends StatefulWidget {
  final VaultController controller;
  const SafeVaultApp({super.key, required this.controller});
  @override
  State<SafeVaultApp> createState() => _SafeVaultAppState();
}

class _SafeVaultAppState extends State<SafeVaultApp>
    with WidgetsBindingObserver {
  bool covered = false;
  bool refreshing = false, lockAfterAuthentication = false;
  int observedBiometricSuccesses = 0;
  final lockNavigator = GlobalKey<NavigatorState>();
  void authenticationChanged() {
    if (!mounted) return;
    // Reconcile the actual lifecycle state even if native prompt completion and
    // Flutter's resume callback arrive in a different order.
    final security = widget.controller.security;
    if (security.biometricSuccesses != observedBiometricSuccesses) {
      observedBiometricSuccesses = security.biometricSuccesses;
      backgroundAt = null;
      lockAfterAuthentication = false;
    }
    final state = WidgetsBinding.instance.lifecycleState;
    setState(() => covered = state != null && state != AppLifecycleState.resumed);
    if (!widget.controller.security.authenticating) {
      if (lockAfterAuthentication) { lockAfterAuthentication = false; widget.controller.lock(); }
      if (!covered) checkNotificationOpen();
    }
  }
  Future<void> refreshAfterResume() async {
    if (refreshing || widget.controller.security.authenticating) return;
    refreshing = true;
    try {
      await widget.controller.security.refreshBiometrics();
      await widget.controller.reconcile();
      if (mounted) widget.controller.refresh();
    } catch (_) {
      // A scheduling failure must never leave a touch-blocking overlay active.
    } finally { refreshing = false; }
  }
  final navigator = GlobalKey<NavigatorState>();
  int handledOpenRequests = 0;
  void openReminderCenter() {
    final c = widget.controller;
    if (!mounted || c.locked || covered ||
        c.reminders.openRequests.value == handledOpenRequests) return;
    final nav = navigator.currentState;
    if (nav == null) return;
    handledOpenRequests = c.reminders.openRequests.value;
    nav.push(MaterialPageRoute<void>(builder: (_) => const ReminderCenter()));
  }
  void checkNotificationOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) => openReminderCenter());
    WidgetsBinding.instance.ensureVisualUpdate();
  }
  final clock = Stopwatch()..start();
  int? backgroundAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.security.authentication.addListener(authenticationChanged);
    widget.controller.reminders.openRequests.addListener(checkNotificationOpen);
    widget.controller.addListener(checkNotificationOpen);
    checkNotificationOpen();
  }

  @override
  void dispose() {
    widget.controller.reminders.openRequests.removeListener(checkNotificationOpen);
    widget.controller.removeListener(checkNotificationOpen);
    widget.controller.security.authentication.removeListener(authenticationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    if (state == AppLifecycleState.inactive) {
      // System authentication also makes the app inactive. Hide its preview,
      // but start the auto-lock timer only for a real background transition.
      if (mounted) setState(() => covered = true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgroundAt ??= clock.elapsedMilliseconds;
      if (mounted) setState(() => covered = true);
    } else if (state == AppLifecycleState.resumed) {
      final elapsed = backgroundAt == null ? null : clock.elapsedMilliseconds - backgroundAt!;
      backgroundAt = null;
      if (elapsed != null && elapsed >= c.lockSeconds * 1000) {
        if (c.security.authenticating) { lockAfterAuthentication = true; }
        else { c.lock(); }
      }
      if (mounted) setState(() => covered = false);
      unawaited(refreshAfterResume());
      checkNotificationOpen();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return MaterialApp(
        navigatorKey: navigator,
        title: 'Safe Vault',
        debugShowCheckedModeBanner: false,
        theme: vaultTheme(Brightness.light, accent: Color(c.accent), glass: c.glass, motion: c.motion, contrast: c.contrast, language: c.language),
        darkTheme: vaultTheme(Brightness.dark, accent: Color(c.accent), glass: c.glass, motion: c.motion, contrast: c.contrast, language: c.language),
        themeAnimationDuration: c.motion && !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations ? const Duration(milliseconds: 220) : Duration.zero,
        themeMode: switch (c.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: const HomeScreen(),
        onUnknownRoute: (_) => MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: VaultTextScaler(MediaQuery.textScalerOf(context), c.textSize), disableAnimations: !c.motion || MediaQuery.disableAnimationsOf(context)),
          child: Stack(
          fit: StackFit.expand,
          children: [
            // Offstage removes both paint and hit testing together; there is no
            // independently latched IgnorePointer that can strand the visible UI.
            Offstage(key: const ValueKey('vault-content'), offstage: c.locked || covered,
              child: ExcludeFocus(excluding: c.locked || covered, child: TickerMode(enabled: !c.locked && !covered, child: child!))),
            if (c.locked)
              Positioned.fill(key: const ValueKey('vault-lock'),
                child: HeroControllerScope.none(child: Navigator(key: lockNavigator, onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => LockScreen(controller: c, onUnlocked: c.unlock))))),
            if (covered)
              const Positioned.fill(key: ValueKey('vault-privacy'),
                child: ColoredBox(
                  color: ink,
                  child: Center(
                    child: Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        )),
      );
    },
  );
}
