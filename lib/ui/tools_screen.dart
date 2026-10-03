import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/controller.dart';
import '../core/model.dart';
import 'design.dart';
import 'editor.dart';
import 'photo_pdf.dart';
import 'receipt_import.dart';
import 'organizer_settings.dart';
class ToolsScreen extends StatelessWidget {
  final VaultController controller;
  const ToolsScreen({super.key,required this.controller});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Tools')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:ListView(padding:const EdgeInsets.all(20),children:[
      VaultCard(child:Column(children:[
        ListTile(leading:const Icon(Icons.receipt_long_outlined),title:const Text('Receipt draft'),subtitle:const Text('Attach receipt · review payment details'),
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ReceiptImport(controller:controller)))),
        ListTile(leading:const Icon(Icons.document_scanner_outlined),title:const Text('Photo to PDF'),subtitle:const Text('Select · crop · combine'),
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>PhotoPdf(controller:controller)))),
        ListTile(leading:const Icon(Icons.storage_outlined),title:const Text('Storage'),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>StorageScreen(controller:controller)))),
      ])),
      const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Quick templates')),
      for(final template in <({String name,Kind kind,String body})>[
        (name:'Passport',kind:Kind.document,body:'Holder:\nDocument number:\nRenewal steps:'),
        (name:'College fee',kind:Kind.task,body:'Semester:\nAmount:\nPayment reference:'),
        (name:'Warranty',kind:Kind.document,body:'Product:\nSerial number:\nSeller:'),
        (name:'Monthly bill',kind:Kind.subscription,body:'Provider:\nAccount reference:'),
      ])VaultCard(child:ListTile(leading:const Icon(Icons.note_add_outlined),title:Text(template.name),trailing:const Icon(Icons.chevron_right),
        onTap:()=>Navigator.push(context,MaterialPageRoute<bool>(builder:(_)=>ItemEditor(controller:controller,kind:template.kind,
          draft:Item(id:const Uuid().v4(),kind:template.kind,title:template.name,body:template.body,
            cycle:template.kind==Kind.subscription?'Monthly':'None')))))),
    ]))));
}
