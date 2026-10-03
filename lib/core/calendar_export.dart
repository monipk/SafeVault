import 'dart:convert';
import 'dart:typed_data';
import 'model.dart';
Uint8List calendarExport(Item item) {
  if(item.due==null) throw const FormatException('Set a due date first.');
  String escape(String s)=>s.replaceAll('\\','\\\\').replaceAll('\r','').replaceAll('\n',r'\n').replaceAll(';',r'\;').replaceAll(',',r'\,');
  String fold(String s){final out=StringBuffer();var length=0;for(final rune in s.runes){final char=String.fromCharCode(rune);final size=utf8.encode(char).length;
    if(length+size>75){out.write('\r\n ');length=1;}out.write(char);length+=size;}return out.toString();}
  final d=item.due!;final end=DateTime(d.year,d.month,d.day+1);
  final stamp=DateTime.now().toUtc().toIso8601String().split('.').first.replaceAll('-','').replaceAll(':','')+'Z';
  return Uint8List.fromList(utf8.encode([
    'BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Safe Vault//Calendar//EN','BEGIN:VEVENT',
    'UID:${escape(item.id)}@safevault.local','DTSTAMP:$stamp','DTSTART;VALUE=DATE:${dateKey(d).replaceAll('-','')}',
    'DTEND;VALUE=DATE:${dateKey(end).replaceAll('-','')}','SUMMARY:${escape(item.title)}',
    'END:VEVENT','END:VCALENDAR',''].map(fold).join('\r\n')));
}
