import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/security.dart';
import 'design.dart';

class PinDots extends StatelessWidget {
  final int length, entered;
  const PinDots({super.key, required this.length, required this.entered});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$entered of $length digits entered',
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        length,
        (i) => AnimatedContainer(
          duration: motionDuration(context),
          key: ValueKey('pin-dot-$i'),
          width: 14,
          height: 14,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < entered
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    ),
  );
}

class LockScreen extends StatefulWidget {
  final VaultController controller;
  final VoidCallback onUnlocked;
  const LockScreen({
    super.key,
    required this.controller,
    required this.onUnlocked,
  });
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '', message = 'Enter your PIN';
  bool busy = false, recovery = false, showPin = true;
  final recoveryCode = TextEditingController();
  final newPin = TextEditingController(), confirmPin = TextEditingController();
  final form = GlobalKey<FormState>();
  Timer? ticker;
  int biometricRequest = 0;
  @override
  void initState() {
    super.initState();
    showPin = !widget.controller.security.biometricEnabled;
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.security.blockedUntil != null) setState(() {});
    });
    if (!showPin) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) bio(); });
  }
  @override
  void dispose() {
    ticker?.cancel(); recoveryCode.dispose(); newPin.dispose(); confirmPin.dispose(); super.dispose();
  }
  Future<void> digit(String value) async {
    final s = widget.controller.security;
    if (busy || s.waitSeconds > 0) return;
    if (value == 'back') {
      setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length-1)); return;
    }
    if (pin.length >= AppLockConfig.pinLength) return;
    setState(() => pin += value);
    if (pin.length != AppLockConfig.pinLength) return;
    setState(() => busy = true);
    try {
      final ok = await s.verify(pin);
      if (!mounted) return;
      if (ok) { widget.onUnlocked(); return; }
      HapticFeedback.heavyImpact();
      setState(() { pin = ''; message = 'Incorrect PIN'; });
    } catch (_) {
      if (mounted) setState(() { pin = ''; message = 'Could not unlock. Try again.'; });
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> bio() async {
    if (busy) return;
    final request = ++biometricRequest;
    setState(() => busy = true);
    try {
      final ok = await widget.controller.security.unlockBiometric();
      if (!mounted || request != biometricRequest) return;
      if (ok) { widget.onUnlocked(); }
      else { setState(() { showPin = true; message = 'Use your PIN or retry biometrics'; }); }
    } catch (_) {
      if (mounted && request == biometricRequest) setState(() { showPin = true; message = 'Use your PIN'; });
    } finally { if (mounted && request == biometricRequest) setState(() => busy = false); }
  }
  Future<void> usePin() async {
    biometricRequest++;
    try { await widget.controller.security.cancelBiometric(); } catch (_) {}
    if (mounted) setState(() { busy = false; showPin = true; message = 'Enter your PIN'; });
  }
  Future<void> reset({required bool biometric}) async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final s = widget.controller.security;
      final ok = biometric ? await s.resetPinWithBiometrics(newPin.text)
        : await s.resetPinWithRecovery(recoveryCode.text, newPin.text);
      if (!mounted) return;
      if (ok) { widget.controller.refresh(); widget.onUnlocked(); }
      else { setState(() => message = biometric ? 'Could not verify. Try again.' : 'Invalid recovery code'); }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not reset PIN. Try again.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final s = widget.controller.security;
    return Material(color: Theme.of(context).scaffoldBackgroundColor, child: SafeArea(
      child: Center(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Column(children: [
          Icon(recovery ? Icons.lock_reset : Icons.shield_outlined, size: 56,
            color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(recovery ? 'Reset PIN' : 'Safe Vault', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          if (recovery) ...[
            if (!s.biometricEnabled && !s.hasRecovery)
              const Text('No recovery method is set up. Your records are still safe on this device. You need your PIN to unlock, or a password-protected backup to restore after starting fresh. Do not clear app data unless you have a backup.', textAlign: TextAlign.center)
            else Form(key: form, child: Column(children: [
              const Text('Verify with biometrics or your saved recovery code. Your files stay intact.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              for (final entry in [(newPin, 'New PIN'), (confirmPin, 'Confirm PIN')]) ...[
                TextFormField(controller: entry.$1, obscureText: true,
                  keyboardType: TextInputType.number, maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: entry.$2),
                  validator: (v) => v?.length != 6 ? 'Enter six digits'
                    : entry.$1 == confirmPin && v != newPin.text ? 'PINs do not match' : null),
                const SizedBox(height: 12),
              ],
              if (s.biometricEnabled) SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: busy ? null : () => reset(biometric: true), icon: const Icon(Icons.fingerprint),
                label: const Text('Verify & reset'))),
              if (s.hasRecovery) ...[
                const SizedBox(height: 16),
                TextFormField(controller: recoveryCode, autocorrect: false, enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Recovery code')),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy || s.waitSeconds > 0
                  ? null : () => reset(biometric: false), child: const Text('Reset with code'))),
              ],
            ])),
          ] else ...[
            if (showPin) ...[
              PinDots(length: AppLockConfig.pinLength, entered: pin.length),
              const SizedBox(height: 12),
              GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.5, children: [
                  for (final n in ['1','2','3','4','5','6','7','8','9']) TextButton(
                    onPressed: busy || s.waitSeconds > 0 ? null : () => digit(n), child: Text(n, style: const TextStyle(fontSize: 28))),
                  s.biometricEnabled ? IconButton(tooltip: 'Use biometrics', onPressed: busy ? null : bio,
                    icon: const Icon(Icons.fingerprint, size: 30)) : const SizedBox.shrink(),
                  TextButton(onPressed: busy || s.waitSeconds > 0 ? null : () => digit('0'),
                    child: const Text('0', style: TextStyle(fontSize: 28))),
                  IconButton(tooltip: 'Delete digit', onPressed: busy ? null : () => digit('back'), icon: const Icon(Icons.backspace_outlined)),
                ]),
            ] else ...[
              IconButton(tooltip: 'Use biometrics', onPressed: busy ? null : bio,
                icon: const Icon(Icons.fingerprint, size: 56)),
              TextButton(onPressed: busy ? null : () => setState(() => showPin = true), child: const Text('Use PIN')),
            ],
          ],
          const SizedBox(height: 12),
          Text(s.waitSeconds > 0 ? 'Try again in ${s.waitSeconds}s' : message, textAlign: TextAlign.center),
          if (busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (busy && s.authenticating) TextButton(onPressed: usePin, child: const Text('Cancel · use PIN')),
          const SizedBox(height: 12),
          TextButton(onPressed: busy ? null : () => setState(() {
            recovery = !recovery; pin = ''; message = recovery ? '' : 'Enter your PIN'; showPin = true;
            recoveryCode.clear(); newPin.clear(); confirmPin.clear();
          }), child: Text(recovery ? 'Back to unlock' : 'Forgot PIN?')),
        ]))))));
  }
}

Future<bool> configurePin(BuildContext context, VaultController c) async {
  final a = TextEditingController(), b = TextEditingController();
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set your six-digit PIN'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: a,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: AppLockConfig.pinLength,
              decoration: const InputDecoration(labelText: 'New PIN'),
              validator: (v) => v?.length == AppLockConfig.pinLength
                  ? null
                  : 'Enter six digits',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: b,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: AppLockConfig.pinLength,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
              validator: (v) => v == a.text ? null : 'PINs do not match',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('Save PIN'),
        ),
      ],
    ),
  );
  final pin = a.text;
  await Future<void>.delayed(const Duration(milliseconds: 250));
  a.dispose();
  b.dispose();
  if (ok != true) {
    return false;
  }
  await c.security.setPin(pin);
  c.refresh();
  return true;
}
