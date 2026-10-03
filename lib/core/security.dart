import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto.dart';

class AppLockConfig {
  static const pinLength = 6;
}

class SecurityService {
  final FlutterSecureStorage storage;
  final LocalAuthentication biometric;
  bool enabled = false, biometricEnabled = false;
  final authentication = ValueNotifier<bool>(false);
  int biometricSuccesses = 0;
  bool get authenticating => authentication.value;
  set authenticating(bool value) => authentication.value = value;

  Future<bool> _authenticate(String reason) async {
    try {
      return await biometric.authenticate(localizedReason: reason,
        biometricOnly: true, persistAcrossBackgrounding: false)
        .timeout(const Duration(seconds: 45), onTimeout: () async {
          await biometric.stopAuthentication().timeout(const Duration(seconds: 2), onTimeout: () => false);
          return false;
        });
    } catch (_) { return false; }
  }
  Future<void> cancelBiometric() async {
    if (authenticating) await biometric.stopAuthentication().timeout(const Duration(seconds: 2), onTimeout: () => false);
  }
  bool hasRecovery = false;
  List<BiometricType> types = [];
  String? biometricIssue;
  int fails = 0;
  DateTime? blockedUntil;
  SecurityService({
    this.storage = const FlutterSecureStorage(),
    LocalAuthentication? biometric,
  }) : biometric = biometric ?? LocalAuthentication();
  Future<void> initialize() async {
    enabled = await storage.read(key: 'pin.v1') != null;
    hasRecovery = await storage.read(key: 'recovery.v1') != null;
    biometricEnabled = await storage.read(key: 'biometric') == 'true';
    fails = int.tryParse(await storage.read(key: 'pin.fails') ?? '0') ?? 0;
    blockedUntil = DateTime.tryParse(
      await storage.read(key: 'pin.blocked') ?? '',
    );
    await refreshBiometrics();
  }

  Future<void> refreshBiometrics() async {
    types = [];
    biometricIssue = null;
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    try {
      if (await biometric.isDeviceSupported() &&
          await biometric.canCheckBiometrics) {
        types = await biometric.getAvailableBiometrics();
      }
    } catch (_) {
      biometricIssue = 'Biometrics are unavailable. Check your device settings.';
      types = [];
    }
  }

  bool get canBiometric => enabled && biometricEnabled && types.isNotEmpty;
  int get waitSeconds => blockedUntil == null
      ? 0
      : (blockedUntil!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 1800);
  Future<void> setPin(String pin) async {
    if (!RegExp('^[0-9]{${AppLockConfig.pinLength}}\$').hasMatch(pin)) {
      throw const FormatException('Enter a six-digit PIN');
    }
    final salt = (await AesGcm.with256bits().newSecretKey()).extractBytes();
    final bytes = await salt;
    final hash = await (await VaultCrypto.derive(pin, bytes)).extractBytes();
    await storage.write(
      key: 'pin.v1',
      value: jsonEncode({
        'salt': base64Encode(bytes),
        'hash': base64Encode(hash),
        'length': AppLockConfig.pinLength,
        'algorithm': 'PBKDF2-SHA256',
        'iterations': 210000,
        'created': DateTime.now().toIso8601String(),
      }),
    );
    enabled = true;
    await clearFailures();
  }

  Future<bool> verify(String pin) async {
    if (waitSeconds > 0) {
      return false;
    }
    final raw = await storage.read(key: 'pin.v1');
    if (raw == null) {
      return false;
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final expected = base64Decode(j['hash'] as String);
    final actual = await (await VaultCrypto.derive(
      pin,
      base64Decode(j['salt'] as String),
    )).extractBytes();
    var difference = expected.length ^ actual.length;
    for (var i = 0; i < expected.length && i < actual.length; i++) {
      difference |= expected[i] ^ actual[i];
    }
    if (difference == 0) {
      await clearFailures();
      return true;
    }
    await recordFailure();
    return false;
  }

  Future<void> recordFailure() async {
    fails++;
    final seconds = fails >= 10 ? 1800 : fails >= 8 ? 300 : fails >= 5 ? 30 : 0;
    blockedUntil = DateTime.now().add(Duration(seconds: seconds));
    await storage.write(key: 'pin.fails', value: '$fails');
    await storage.write(key: 'pin.blocked', value: blockedUntil!.toIso8601String());
  }

  // 160 bits of entropy; only a salted verifier is stored on the device.
  String newRecoveryCode() {
    final random = Random.secure();
    final hex = List.generate(20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return List.generate(8, (i) => hex.substring(i * 5, i * 5 + 5)).join('-');
  }
  String _normalizeCode(String code) => code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  Future<void> setRecoveryCode(String code) async {
    if (!enabled) throw const FormatException('Set a PIN first.');
    final normalized = _normalizeCode(code);
    if (!RegExp(r'^[0-9A-F]{40}$').hasMatch(normalized)) {
      throw const FormatException('Invalid recovery code.');
    }
    final salt = await (await AesGcm.with256bits().newSecretKey()).extractBytes();
    final hash = await (await VaultCrypto.derive(normalized, salt)).extractBytes();
    await storage.write(key: 'recovery.v1', value: jsonEncode({
      'salt': base64Encode(salt), 'hash': base64Encode(hash),
    }));
    hasRecovery = true;
  }
  Future<bool> resetPinWithRecovery(String code, String newPin) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(newPin)) throw const FormatException('Enter six digits.');
    if (!enabled || waitSeconds > 0) return false;
    final raw = await storage.read(key: 'recovery.v1');
    if (raw == null) return false;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final expected = base64Decode(j['hash'] as String);
    final actual = await (await VaultCrypto.derive(_normalizeCode(code), base64Decode(j['salt'] as String))).extractBytes();
    var difference = expected.length ^ actual.length;
    for (var i = 0; i < expected.length && i < actual.length; i++) {
      difference |= expected[i] ^ actual[i];
    }
    if (difference != 0) { await recordFailure(); return false; }
    // Consume before changing the PIN: a storage failure cannot leave a reusable code.
    await storage.delete(key: 'recovery.v1');
    hasRecovery = false;
    await setPin(newPin);
    return true;
  }
  Future<bool> resetPinWithBiometrics(String newPin) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(newPin)) throw const FormatException('Enter six digits.');
    if (!await unlockBiometric()) return false;
    await setPin(newPin);
    return true;
  }

  Future<void> clearFailures() async {
    fails = 0;
    blockedUntil = null;
    await storage.delete(key: 'pin.fails');
    await storage.delete(key: 'pin.blocked');
  }

  Future<bool> unlockBiometric() async {
    if (authenticating) return false;
    // Acquire before awaiting enrollment checks: never start overlapping prompts.
    authenticating = true;
    try {
      await refreshBiometrics();
      if (!canBiometric) return false;
      final ok = await _authenticate('Unlock Safe Vault');
      if (ok) { await clearFailures(); biometricSuccesses++; }
      return ok;
    } finally { authenticating = false; }
  }

  Future<void> setBiometric(bool value) async {
    if (authenticating) throw const FormatException('Finish the current unlock first.');
    if (value) {
      authenticating = true;
      try {
        await refreshBiometrics();
        if (!enabled || types.isEmpty) {
          throw const FormatException('Enroll a fingerprint or Face ID in your device settings first.');
        }
        if (!await _authenticate('Enable biometric unlock')) return;
        biometricSuccesses++;
      } finally { authenticating = false; }
    }
    await storage.write(key: 'biometric', value: '$value');
    biometricEnabled = value;
  }

  Future<void> disable() async {
    await storage.delete(key: 'pin.v1');
    await storage.delete(key: 'recovery.v1');
    hasRecovery = false;
    await setBiometric(false);
    await clearFailures();
    enabled = false;
  }

  Future<void> screenshotProtection(bool enabled) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel(
        'safe_vault/privacy',
      ).invokeMethod<void>('secure', enabled);
    }
  }
}
