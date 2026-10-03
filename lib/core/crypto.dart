import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cipher.dart';

class VaultCrypto {
  final FlutterSecureStorage storage;
  final cipher = VaultCipher();
  SecretKey? _key;
  VaultCrypto([this.storage = const FlutterSecureStorage()]);
  Future<void> initialize({required bool hasRecords}) async {
    final stored = await storage.read(key: 'vault.key.v1');
    if (stored == null) {
      if (hasRecords) {
        throw StateError(
          'Encryption key is missing. Restore an encrypted backup on a fresh installation; existing data was not changed.',
        );
      }
      _key = await cipher.algorithm.newSecretKey();
      await storage.write(
        key: 'vault.key.v1',
        value: base64Encode(await _key!.extractBytes()),
      );
    } else {
      _key = SecretKey(base64Decode(stored));
    }
  }

  Future<String> encrypt(
    List<int> bytes, {
    SecretKey? key,
    String aad = 'safe-vault-v1',
  }) => cipher.encrypt(bytes, key: key ?? _key!, aad: aad);
  Future<List<int>> decrypt(
    String data, {
    SecretKey? key,
    String aad = 'safe-vault-v1',
  }) => cipher.decrypt(data, key: key ?? _key!, aad: aad);
  static Future<SecretKey> derive(String password, List<int> salt) =>
      VaultCipher.derive(password, salt);
}
