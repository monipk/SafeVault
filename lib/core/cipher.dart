import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Platform-independent authenticated encryption, shared by records and backups.
class VaultCipher {
  final algorithm = AesGcm.with256bits();
  Future<String> encrypt(
    List<int> bytes, {
    required SecretKey key,
    required String aad,
  }) async {
    final box = await algorithm.encrypt(
      bytes,
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return jsonEncode({
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  Future<List<int>> decrypt(
    String data, {
    required SecretKey key,
    required String aad,
  }) async {
    final j = jsonDecode(data) as Map<String, dynamic>;
    return algorithm.decrypt(
      SecretBox(
        base64Decode(j['c'] as String),
        nonce: base64Decode(j['n'] as String),
        mac: Mac(base64Decode(j['m'] as String)),
      ),
      secretKey: key,
      aad: utf8.encode(aad),
    );
  }

  static Future<SecretKey> derive(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}
