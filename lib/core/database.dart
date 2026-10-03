import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Handwritten SQL schema; no generated files or build_runner required.
class VaultDatabase extends GeneratedDatabase {
  VaultDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'safe_vault_v1',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  Future<void> createAssets() => customStatement(
    'CREATE TABLE IF NOT EXISTS assets (id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE, payload TEXT NOT NULL)');
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE records (id TEXT PRIMARY KEY, notification_id INTEGER NOT NULL UNIQUE, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE attachments (id TEXT PRIMARY KEY REFERENCES records(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE preferences (id TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE sequence (id INTEGER PRIMARY KEY CHECK(id=1), next_id INTEGER NOT NULL)',
      );
      await customStatement('INSERT INTO sequence VALUES (1, 1)');
      await createAssets();
    },
    onUpgrade: (_, from, to) async { if (from < 2) await createAssets(); },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
