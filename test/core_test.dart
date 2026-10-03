import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:safe_vault/core/model.dart';
import 'package:safe_vault/core/database.dart';
import 'package:safe_vault/core/crypto.dart';
import 'package:safe_vault/core/repository.dart';
import 'package:safe_vault/core/backup.dart';
import 'package:safe_vault/core/security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('money uses exact minor units and rejects malformed input', () {
    expect(parseMoney('199.99'), 19999);
    expect(parseMoney('0.10'), 10);
    expect(parseMoney('1.2'), 120);
    for (final s in ['-1', 'NaN', '1.234', '1e3', '']) {
      expect(() => parseMoney(s), throwsFormatException);
    }
  });
  test('month-end recurrence retains original anchor', () {
    final feb = advanceDate(DateTime(2024, 1, 31), 'Monthly', anchorDay: 31);
    expect(feb, DateTime(2024, 2, 29));
    expect(advanceDate(feb, 'Monthly', anchorDay: 31), DateTime(2024, 3, 31));
    expect(
      advanceDate(DateTime(2024, 2, 29), 'Yearly', anchorDay: 29),
      DateTime(2025, 2, 28),
    );
  });
  test('quarterly and weekly dates cross years', () {
    expect(
      advanceDate(DateTime(2025, 11, 30), 'Quarterly', anchorDay: 30),
      DateTime(2026, 2, 28),
    );
    expect(advanceDate(DateTime(2025, 12, 28), 'Weekly'), DateTime(2026, 1, 4));
  });
  test('item round trip and validation', () {
    final i = Item(
      id: 'abc',
      kind: Kind.document,
      title: 'Passport',
      due: DateTime(2030, 1, 1),
    );
    expect(Item.fromJson(i.toJson()).toJson(), i.toJson());
    expect(
      () => Item.fromJson({...i.toJson(), 'title': ''}),
      throwsFormatException,
    );
    expect(
      () => Item.fromJson({...i.toJson(), 'amount': -1}),
      throwsFormatException,
    );
  });
  test(
    'AES-GCM rejects tampered ciphertext and wrong associated record',
    () async {
      final c = VaultCrypto();
      final key = await AesGcm.with256bits().newSecretKey();
      final encoded = await c.encrypt(
        utf8.encode('private'),
        key: key,
        aad: 'item:one',
      );
      expect(
        utf8.decode(await c.decrypt(encoded, key: key, aad: 'item:one')),
        'private',
      );
      await expectLater(
        c.decrypt(encoded, key: key, aad: 'item:two'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final j = jsonDecode(encoded) as Map<String, dynamic>;
      j['c'] = base64Encode([1, 2, 3]);
      await expectLater(
        c.decrypt(jsonEncode(j), key: key, aad: 'item:one'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  group('persistent repository and backup', () {
    late VaultRepository repo;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      repo = VaultRepository(
        VaultDatabase(NativeDatabase.memory()),
        VaultCrypto(),
      );
      await repo.initialize();
    });
    tearDown(() async {
      await repo.dispose();
    });
    test(
      'empty on first use, encrypted CRUD and stable notification identity',
      () async {
        expect(await repo.all(), isEmpty);
        final i = Item(
          id: 'one',
          kind: Kind.note,
          title: 'Secret note',
          body: 'Private body',
        );
        await repo.save(i);
        final ids = await repo.notificationIds();
        await repo.save(i.patch({'title': 'Revised'}));
        expect(await repo.notificationIds(), ids);
        expect((await repo.all()).single.title, 'Revised');
        final raw =
            (await repo.db
                    .customSelect('SELECT payload FROM records')
                    .getSingle())
                .read<String>('payload');
        expect(raw, isNot(contains('Private body')));
        await repo.purge('one');
        expect(await repo.all(), isEmpty);
      },
    );
    test(
      'backup round trip preserves file bytes and rejects wrong password',
      () async {
        final i = Item(
          id: 'one',
          kind: Kind.document,
          title: 'Document',
          attachmentName: 'test.bin',
        );
        final bytes = Uint8List.fromList([0, 255, 1, 2, 3]);
        await repo.save(i, attachment: bytes);
        final b = BackupService(repo);
        final archive = await b.create('a strong password');
        await expectLater(
          b.preview(archive, 'wrong password'),
          throwsFormatException,
        );
        expect((await repo.all()).length, 1);
        final preview = await b.preview(archive, 'a strong password');
        await repo.erase();
        await repo.restore(preview.items, preview.attachments);
        expect((await repo.all()).single.toJson(), i.toJson());
        expect(await repo.attachment('one'), bytes);
      },
    );
    test('attachment foreign key cascade prevents orphan files', () async {
      await repo.save(
        Item(id: 'one', kind: Kind.document, title: 'A', attachmentName: 'x'),
        attachment: Uint8List.fromList([1]),
      );
      await repo.purge('one');
      expect(await repo.attachment('one'), isNull);
    });
    test('trash retention keeps recent deletions', () async {
      await repo.save(
        Item(
          id: 'old',
          kind: Kind.note,
          title: 'Old',
          deleted: DateTime.now().subtract(const Duration(days: 31)),
        ),
      );
      await repo.save(
        Item(
          id: 'recent',
          kind: Kind.note,
          title: 'Recent',
          deleted: DateTime.now(),
        ),
      );
      await repo.purgeExpiredTrash();
      expect((await repo.all()).map((i) => i.id), ['recent']);
    });
  });
  test('PIN verifier is hashed and failures survive a new service', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecurityService();
    await s.setPin('123456');
    expect(await s.verify('123456'), true);
    for (var i = 0; i < 5; i++) {
      expect(await s.verify('000000'), false);
    }
    expect(s.waitSeconds, greaterThan(0));
    final fresh = SecurityService();
    await fresh.initialize();
    expect(fresh.fails, 5);
    expect(fresh.waitSeconds, greaterThan(0));
    final raw = await s.storage.read(key: 'pin.v1');
    expect(raw, isNot(contains('123456')));
  });
  test('CSV quotes values and neutralizes formula injection', () {
    final s = utf8.decode(
      BackupService.csv([
        Item(id: 'x', kind: Kind.note, title: '=SUM(1)', body: 'a,"b"'),
      ]),
    );
    expect(s, contains("'=SUM(1)"));
    expect(s, contains('a,""b""'));
  });
}
