import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:safe_vault/core/security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('recovery changes the PIN once and preserves other secure keys', () async {
    final s = SecurityService();
    await s.setPin('123456');
    await s.storage.write(key: 'unrelated-vault-key', value: 'keep-me');
    final code = s.newRecoveryCode();
    await s.setRecoveryCode(code);
    expect(await s.storage.read(key: 'recovery.v1'), isNot(contains(code.replaceAll('-', ''))));
    expect(await s.resetPinWithRecovery('WRONG', '654321'), isFalse);
    expect(await s.verify('123456'), isTrue);
    expect(await s.resetPinWithRecovery(code.toLowerCase().replaceAll('-', ' '), '654321'), isTrue);
    expect(await s.verify('654321'), isTrue);
    expect(await s.verify('123456'), isFalse);
    expect(await s.resetPinWithRecovery(code, '111111'), isFalse);
    expect(s.hasRecovery, isFalse);
    expect(await s.storage.read(key: 'unrelated-vault-key'), 'keep-me');
  }, timeout: const Timeout(Duration(minutes: 5)));
  test('invalid recovery attempts share persisted PIN rate limits', () async {
    final s = SecurityService();
    await s.setPin('123456');
    final code = s.newRecoveryCode();
    await s.setRecoveryCode(code);
    for (var i = 0; i < 5; i++) {
      expect(await s.resetPinWithRecovery('WRONG', '654321'), isFalse);
    }
    expect(s.waitSeconds, greaterThan(0));
    final fresh = SecurityService();
    await fresh.initialize();
    expect(fresh.hasRecovery, isTrue);
    expect(fresh.waitSeconds, greaterThan(0));
    expect(await fresh.resetPinWithRecovery(code, '654321'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
  test('replacing a recovery code invalidates the old one', () async {
    final s = SecurityService();
    await s.setPin('123456');
    final first = s.newRecoveryCode(), second = s.newRecoveryCode();
    await s.setRecoveryCode(first);
    await s.setRecoveryCode(second);
    expect(await s.resetPinWithRecovery(first, '654321'), isFalse);
    expect(await s.resetPinWithRecovery(second, '654321'), isTrue);
    await s.setRecoveryCode(s.newRecoveryCode());
    await s.disable();
    expect(await s.storage.read(key: 'recovery.v1'), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
