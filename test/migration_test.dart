import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:safe_vault/core/database.dart';
import 'package:safe_vault/core/crypto.dart';
import 'package:safe_vault/core/repository.dart';
import 'package:safe_vault/core/model.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('version one database keeps records and original file during migration',()async{
    FlutterSecureStorage.setMockInitialValues({});
    final crypto=VaultCrypto();await crypto.initialize(hasRecords:false);
    final old=Item(id:'old',kind:Kind.document,title:'Existing passport',attachmentName:'original.txt').toJson()..remove('extra');
    final payload=await crypto.encrypt(utf8.encode(jsonEncode(old)),aad:'record:old');
    final file=await crypto.encrypt([1,2,3],aad:'attachment:old');
    final executor=NativeDatabase.memory(setup:(db){
      db.execute('CREATE TABLE records(id TEXT PRIMARY KEY, notification_id INTEGER NOT NULL UNIQUE, payload TEXT NOT NULL)');
      db.execute('CREATE TABLE attachments(id TEXT PRIMARY KEY REFERENCES records(id) ON DELETE CASCADE, payload TEXT NOT NULL)');
      db.execute('CREATE TABLE preferences(id TEXT PRIMARY KEY, value TEXT NOT NULL)');
      db.execute('CREATE TABLE sequence(id INTEGER PRIMARY KEY CHECK(id=1), next_id INTEGER NOT NULL)');
      db.execute('INSERT INTO records VALUES(?,?,?)',['old',1,payload]);
      db.execute('INSERT INTO attachments VALUES(?,?)',['old',file]);
      db.execute('INSERT INTO sequence VALUES(1,2)');
      db.execute('PRAGMA user_version=1');
    });
    final repo=VaultRepository(VaultDatabase(executor),crypto);
    try{
      await repo.initialize();expect((await repo.all()).single.title,'Existing passport');
      expect(await repo.attachment('old'),[1,2,3]);expect(await repo.assets(),isEmpty);
      expect((await repo.all()).single.folder,'');
    }finally{await repo.dispose();}
  });
}
