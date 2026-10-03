import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';
import 'package:safe_vault/core/database.dart';
import 'package:safe_vault/core/repository.dart';
import 'package:safe_vault/core/crypto.dart';
import 'package:safe_vault/core/model.dart';
import 'package:safe_vault/core/backup.dart';
import 'package:safe_vault/core/receipt.dart';
import 'package:safe_vault/core/reminder_rules.dart';
import 'package:safe_vault/core/calendar_export.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('quiet hours cross midnight and preserve outside times',(){
    expect(outsideQuietHours(DateTime(2030,1,1,23),1320,480),DateTime(2030,1,2,8));
    expect(outsideQuietHours(DateTime(2030,1,2,7),1320,480),DateTime(2030,1,2,8));
    expect(outsideQuietHours(DateTime(2030,1,2,10),1320,480),DateTime(2030,1,2,10));
    expect(outsideQuietHours(DateTime(2030,1,2,10),600,600),DateTime(2030,1,2,10));
  });
  test('old records default metadata; reminder timestamps round trip',(){
    final old=Item(id:'a',kind:Kind.note,title:'A').toJson()..remove('extra');
    expect(Item.fromJson(old).folder,'');
    final item=Item.fromJson(old).withExtra({'folder':'College','alerts':[DateTime(2030,1,2).toUtc().toIso8601String()]});
    expect(Item.fromJson(item.toJson()).additionalReminders,[DateTime(2030,1,2)]);
  });
  test('receipt parser returns suggestions, not invented merchants',(){
    final draft=ReceiptDraft.parse('Paid to: Example\nINR 1,299.00');
    expect(draft.merchant,'Example');expect(draft.amount,'1299.00');
    expect(ReceiptDraft.parse('unreadable').merchant,'');
  });
  test('calendar export escapes text and creates an exclusive end date',(){
    final text=utf8.decode(calendarExport(Item(id:'a',kind:Kind.task,title:'Renew, A;B',due:DateTime(2030,12,31))));
    expect(text,contains('DTEND;VALUE=DATE:20310101'));expect(text,contains(r'SUMMARY:Renew\, A\;B'));
  });
  test('files and version history survive encrypted backup restore',()async{
    FlutterSecureStorage.setMockInitialValues({});
    final repo=VaultRepository(VaultDatabase(NativeDatabase.memory()),VaultCrypto());
    await repo.initialize();
    try{
      final item=Item(id:'one',kind:Kind.document,title:'Paper',attachmentName:'old.txt');
      await repo.save(item,attachment:Uint8List.fromList([1,2]));
      await repo.save(item.patch({'attachmentName':'new.txt'}),attachment:Uint8List.fromList([3,4]));
      await repo.addAsset('one','second.txt',Uint8List.fromList([5,6]));
      expect((await repo.assets()).length,2);expect(await repo.duplicate(Uint8List.fromList([1,2])),isTrue);
      final service=BackupService(repo);final data=await service.preview(await service.create('a strong password'),'a strong password');
      await repo.restore(data.items,data.attachments,assets:data.assets);
      expect(await repo.attachment('one'),[3,4]);
      expect((await repo.assets()).where((a)=>a.historical).single.name,'old.txt');
      await repo.purge('one');expect(await repo.assets(),isEmpty);
    }finally{await repo.dispose();}
  },timeout:const Timeout(Duration(minutes:5)));
}
