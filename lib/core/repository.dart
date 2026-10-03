import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';
import 'assets.dart';

import 'package:drift/drift.dart';

import 'crypto.dart';
import 'database.dart';
import 'model.dart';

class VaultRepository {
  final VaultDatabase db;
  final VaultCrypto crypto;
  final changes = StreamController<int>.broadcast();
  int _revision = 0;
  List<Item>? _cache;
  VaultRepository(this.db, this.crypto);
  Future<void> initialize() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM records')
        .getSingle();
    await crypto.initialize(hasRecords: rows.read<int>('n') > 0);
  }

  void notify() {
    _cache = null;
    changes.add(++_revision);
  }

  Future<List<Item>> all() async {
    if (_cache != null) {
      return _cache!;
    }
    final revision = _revision;
    final rows = await db.customSelect('SELECT id, payload FROM records').get();
    final result = <Item>[];
    for (final r in rows) {
      result.add(
        Item.fromJson(
          jsonDecode(
                utf8.decode(
                  await crypto.decrypt(
                    r.read<String>('payload'),
                    aad: 'record:${r.read<String>('id')}',
                  ),
                ),
              )
              as Map<String, dynamic>,
        ),
      );
    }
    result.sort((a, b) => b.updated.compareTo(a.updated));
    final immutable = List<Item>.unmodifiable(result);
    if (_revision == revision) {
      _cache = immutable;
    }
    return immutable;
  }

  Future<void> save(
    Item item, {
    Uint8List? attachment,
    bool removeAttachment = false,
    bool keepHistory = true,
  }) async {
    if (attachment != null && attachment.length > 10 * 1024 * 1024) {
      throw const FormatException('Attachments are limited to 10 MB.');
    }
    final previous = (attachment != null || removeAttachment)
      ? (await all()).where((i) => i.id == item.id).firstOrNull : null;
    final previousBytes = previous == null ? null : await this.attachment(item.id);
    final payload = await crypto.encrypt(
      utf8.encode(encodeItem(item)),
      aad: 'record:${item.id}',
    );
    final file = attachment == null
        ? null
        : await crypto.encrypt(attachment, aad: 'attachment:${item.id}');
    await db.transaction(() async {
      final existing = await db
          .customSelect(
            'SELECT notification_id FROM records WHERE id = ?',
            variables: [Variable(item.id)],
          )
          .getSingleOrNull();
      int nid;
      if (existing != null) {
        nid = existing.read<int>('notification_id');
      } else {
        nid =
            (await db
                    .customSelect('SELECT next_id FROM sequence WHERE id=1')
                    .getSingle())
                .read<int>('next_id');
        if (nid >= 2147483647) {
          throw StateError('Notification identifier limit reached');
        }
        await db.customStatement(
          'UPDATE sequence SET next_id = next_id + 1 WHERE id=1',
        );
      }
      await db.customStatement(
        'INSERT INTO records(id, notification_id, payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
        [item.id, nid, payload],
      );
      if (keepHistory && (file != null || removeAttachment)) {
        if (previous != null && previousBytes != null && previous.attachmentName.isNotEmpty) {
          final history = await assets(owner: item.id);
          if (history.length >= 30) throw const FormatException('Remove an old file version before replacing this file.');
          await writeAsset(VaultAsset(id: const Uuid().v4(), owner: item.id, name: previous.attachmentName,
            bytes: previousBytes, hash: await fingerprint(previousBytes), created: DateTime.now(), group: 'primary', historical: true));
        }
      }
      if (removeAttachment) {
        await db.customStatement('DELETE FROM attachments WHERE id=?', [
          item.id,
        ]);
      }
      if (file != null) {
        await db.customStatement(
          'INSERT INTO attachments VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
          [item.id, file],
        );
      }
    });
    notify();
  }

  Future<Uint8List?> attachment(String id) async {
    final row = await db
        .customSelect(
          'SELECT payload FROM attachments WHERE id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : Uint8List.fromList(
            await crypto.decrypt(
              row.read<String>('payload'),
              aad: 'attachment:$id',
            ),
          );
  }

  Future<List<VaultAsset>> assets({String? owner}) async {
    final rows = await db.customSelect(owner == null ? 'SELECT id,payload FROM assets' : 'SELECT id,payload FROM assets WHERE owner=?',
      variables: owner == null ? [] : [Variable(owner)]).get();
    final result = <VaultAsset>[];
    for (final row in rows) {
      result.add(VaultAsset.fromJson(jsonDecode(utf8.decode(await crypto.decrypt(
        row.read<String>('payload'), aad: 'asset:${row.read<String>('id')}'))) as Map<String,dynamic>));
    }
    result.sort((a,b) => b.created.compareTo(a.created));
    return result;
  }
  Future<String> fingerprint(Uint8List bytes) async => base64Encode((await Sha256().hash(bytes)).bytes);
  Future<bool> duplicate(Uint8List bytes) async {
    final hash = await fingerprint(bytes);
    for (final asset in await assets()) { if (asset.hash == hash) return true; }
    for (final item in (await all()).where((i) => i.attachmentName.isNotEmpty)) {
      final primary = await attachment(item.id);
      if (primary != null && await fingerprint(primary) == hash) return true;
    }
    return false;
  }
  Future<void> addAsset(String owner, String name, Uint8List bytes, {String? replaceId}) async {
    if (bytes.length > 10 * 1024 * 1024) throw const FormatException('Each file can be up to 10 MB.');
    final existing = await assets(owner: owner);
    if (existing.length >= 30) throw const FormatException('Keep up to 30 files and versions per item.');
    final old = replaceId == null ? null : existing.where((a) => a.id == replaceId).firstOrNull;
    if (replaceId != null && old == null) throw const FormatException('File no longer exists.');
    final asset = VaultAsset(id: const Uuid().v4(), owner: owner, name: name, bytes: bytes,
      hash: await fingerprint(bytes), created: DateTime.now(), group: old?.group ?? const Uuid().v4());
    await db.transaction(() async {
      if (old != null) await writeAsset(old.asHistory());
      await writeAsset(asset);
    });
    notify();
  }
  Future<void> writeAsset(VaultAsset asset) async {
    final payload = await crypto.encrypt(utf8.encode(jsonEncode(asset.toJson())), aad: 'asset:${asset.id}');
    await db.customStatement('INSERT INTO assets VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
      [asset.id, asset.owner, payload]);
  }
  Future<void> removeAsset(String id) async {
    await db.customStatement('DELETE FROM assets WHERE id=?', [id]); notify();
  }

  Future<Map<String, int>> notificationIds() async => {
    for (final r
        in await db
            .customSelect('SELECT id, notification_id FROM records')
            .get())
      r.read<String>('id'): r.read<int>('notification_id'),
  };
  Future<String?> preference(String id) async =>
      (await db
              .customSelect(
                'SELECT value FROM preferences WHERE id=?',
                variables: [Variable(id)],
              )
              .getSingleOrNull())
          ?.read<String>('value');
  Future<void> setPreference(String id, String value) async {
    await db.customStatement(
      'INSERT INTO preferences VALUES(?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value',
      [id, value],
    );
  }

  Future<void> purge(String id) async {
    await db.customStatement('DELETE FROM records WHERE id=?', [id]);
    notify();
  }

  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    for (final i in await all()) {
      if (i.deleted != null && i.deleted!.isBefore(cutoff)) {
        await purge(i.id);
      }
    }
  }

  Future<void> erase() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM records');
    });
    notify();
  }

  Future<void> restore(List<Item> items, Map<String, Uint8List> files, {List<VaultAsset> assets = const []}) async {
    // Encryption is finished before opening the transaction. Any failure preserves the old vault.
    final encrypted = <String, String>{}, attachments = <String, String>{};
    for (final i in items) {
      encrypted[i.id] = await crypto.encrypt(
        utf8.encode(encodeItem(i)),
        aad: 'record:${i.id}',
      );
    }
    for (final e in files.entries) {
      attachments[e.key] = await crypto.encrypt(
        e.value,
        aad: 'attachment:${e.key}',
      );
    }
    await db.transaction(() async {
      await db.customStatement('DELETE FROM records');
      var nid = 1;
      for (final i in items) {
        await db.customStatement('INSERT INTO records VALUES(?,?,?)', [
          i.id,
          nid++,
          encrypted[i.id],
        ]);
      }
      for (final e in attachments.entries) {
        await db.customStatement('INSERT INTO attachments VALUES(?,?)', [
          e.key,
          e.value,
        ]);
      }
      for (final asset in assets) { await writeAsset(asset); }
      await db.customStatement('UPDATE sequence SET next_id=? WHERE id=1', [
        nid,
      ]);
    });
    notify();
  }

  Future<void> dispose() async {
    await changes.close();
    await db.close();
  }
}
