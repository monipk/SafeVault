import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;

import 'crypto.dart';
import 'model.dart';
import 'repository.dart';
import 'assets.dart';

class BackupData {
  final List<Item> items;
  final Map<String, Uint8List> attachments;
  final List<VaultAsset> assets;
  BackupData(this.items, this.attachments, [this.assets = const []]);
}

class FileService {
  Future<({String name, Uint8List bytes})?> pick({
    int maxBytes = 10 * 1024 * 1024,
  }) async {
    final f = await FilePicker.pickFile();
    if (f == null) { return null; }
    final size = await f.length();
    if (size != null && size > maxBytes) {
      throw FormatException('Choose a file smaller than ${maxBytes ~/ (1024 * 1024)} MB.');
    }
    final bytes = await f.readAsBytes();
    if (bytes.length > maxBytes) {
      throw FormatException(
        'Choose a file smaller than ${maxBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return (name: f.name, bytes: bytes);
  }

  Future<bool> save(
    String name,
    Uint8List bytes, {
    String mime = 'application/octet-stream',
  }) async =>
      await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime) !=
      null;
}

class BackupService {
  final VaultRepository repo;
  BackupService(this.repo);
  Future<Uint8List> create(String password) async {
    if (password.length < 12) {
      throw const FormatException(
        'Use a backup password with at least 12 characters.',
      );
    }
    final items = await repo.all();
    final files = <String, String>{};
    var total = 0;
    for (final i in items.where((i) => i.attachmentName.isNotEmpty)) {
      final b = await repo.attachment(i.id);
      if (b == null) {
        throw const FormatException(
          'An attachment is missing. Backup stopped to protect data integrity.',
        );
      }
      total += b.length;
      if (total > 40 * 1024 * 1024) {
        throw const FormatException(
          'This version supports backups up to 40 MB of attachments. Export larger attachments individually.',
        );
      }
      files[i.id] = base64Encode(b);
    }
    final assets = await repo.assets();
    total += assets.fold<int>(0, (n, a) => n + a.bytes.length);
    if (total > 40*1024*1024) throw const FormatException('Backup exceeds 40 MB. Export and remove large files first.');
    final salt = await (await AesGcm.with256bits().newSecretKey())
        .extractBytes();
    final key = await VaultCrypto.derive(password, salt);
    final data = jsonEncode({
      'schema': 2,
      'assets': assets.map((a) => a.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'files': files,
    });
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'safe-vault',
          'version': 1,
          'salt': base64Encode(salt),
          'payload': await repo.crypto.encrypt(
            utf8.encode(data),
            key: key,
            aad: 'safe-vault-backup-v1',
          ),
        }),
      ),
    );
  }

  Future<BackupData> preview(Uint8List bytes, String password) async {
    if (bytes.length > 80 * 1024 * 1024) {
      throw const FormatException('Backup exceeds the 80 MB import limit.');
    }
    try {
      final outer = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (outer['format'] != 'safe-vault' || outer['version'] != 1) {
        throw const FormatException();
      }
      final salt = base64Decode(outer['salt'] as String);
      if (salt.length != 32) {
        throw const FormatException();
      }
      final key = await VaultCrypto.derive(password, salt);
      final raw = await repo.crypto.decrypt(
        outer['payload'] as String,
        key: key,
        aad: 'safe-vault-backup-v1',
      );
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      if (j['schema'] != 1 && j['schema'] != 2) {
        throw const FormatException();
      }
      final items = (j['items'] as List)
          .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (items.length > 10000 ||
          items.map((i) => i.id).toSet().length != items.length) {
        throw const FormatException();
      }
      final files = (j['files'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, base64Decode(v as String)),
      );
      final assets = ((j['assets'] as List?) ?? []).map((v) => VaultAsset.fromJson(Map<String,dynamic>.from(v as Map))).toList();
      if (assets.map((a) => a.id).toSet().length != assets.length) throw const FormatException();
      for (final asset in assets) {
        if (!items.any((i) => i.id == asset.owner) || await repo.fingerprint(asset.bytes) != asset.hash) throw const FormatException();
      }
      var total = assets.fold<int>(0, (n,a) => n + a.bytes.length);
      for (final e in files.entries) {
        total += e.value.length;
        if (!items.any((i) => i.id == e.key && i.attachmentName.isNotEmpty) ||
            e.value.length > 10 * 1024 * 1024) {
          throw const FormatException();
        }
      }
      if (total > 40 * 1024 * 1024 ||
          items.any(
            (i) => i.attachmentName.isNotEmpty && !files.containsKey(i.id),
          )) {
        throw const FormatException();
      }
      return BackupData(items, files, assets);
    } catch (_) {
      throw const FormatException(
        'Wrong password, damaged backup, or unsupported backup format. Your current vault is unchanged.',
      );
    }
  }

  static Uint8List csv(List<Item> items) {
    String cell(String v) {
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(v)) {
        v = "'$v";
      }
      return '"${v.replaceAll('"', '""')}"';
    }

    final rows = <List<String>>[
      [
        'Type',
        'Title',
        'Category',
        'Tags',
        'Due date',
        'Amount (minor units)',
        'Currency',
        'Status',
        'Notes',
      ],
      ...items.map(
        (i) => [
          i.kind.singular,
          i.title,
          i.category,
          i.tags,
          i.due == null ? '' : dateKey(i.due!),
          '${i.amount}',
          i.currency,
          i.status,
          i.body,
        ],
      ),
    ];
    return Uint8List.fromList(
      utf8.encode(rows.map((r) => r.map(cell).join(',')).join('\r\n')),
    );
  }

  static Future<Uint8List> summary(List<Item> items) async {
    // Built-in PDF fonts are ASCII only; sanitize labels rather than fail on export.
    String safe(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        maxPages: 1000,
        build: (_) => [
          pw.Header(level: 0, text: 'Safe Vault | Personal summary'),
          pw.Text(
            'Exported ${dateKey(DateTime.now())}. Notes and attachments are excluded.',
          ),
          pw.SizedBox(height: 20),
          ...items.map(
            (i) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                safe(
                  '${i.kind.singular}: ${i.title} | ${i.dateLabel}${i.kind == Kind.subscription ? ' | ${i.currency} ${(i.amount / 100).toStringAsFixed(2)} / ${i.cycle}' : ''}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
