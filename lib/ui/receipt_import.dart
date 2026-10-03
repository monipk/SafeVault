import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/controller.dart';
import '../core/model.dart';
import '../core/receipt.dart';
import 'common.dart';
import 'editor.dart';
class ReceiptImport extends StatefulWidget {
  final VaultController controller;
  const ReceiptImport({super.key,required this.controller});
  @override State<ReceiptImport> createState()=>_ReceiptImportState();
}
class _ReceiptImportState extends State<ReceiptImport> {
  final text=TextEditingController();String name='';Uint8List? bytes;bool busy=false;
  @override void dispose(){text.dispose();super.dispose();}
  Future<void> pick() async {
    setState(()=>busy=true);
    await attempt(context,()async{final f=await widget.controller.files.pick();if(f==null||!mounted)return;
      setState((){name=f.name;bytes=f.bytes;if(name.toLowerCase().endsWith('.txt'))text.text=utf8.decode(f.bytes,allowMalformed:true);});});
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Receipt draft')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Attach your receipt and paste its text to suggest payment details. Screenshots and PDFs are stored as evidence; this version does not read their text automatically.'),
      const SizedBox(height:20),OutlinedButton.icon(onPressed:busy?null:pick,icon:const Icon(Icons.attach_file),label:Text(name.isEmpty?'Attach receipt':name)),
      const SizedBox(height:20),TextField(controller:text,minLines:6,maxLines:12,maxLength:20000,decoration:const InputDecoration(labelText:'Receipt text',hintText:'Paid to: Example\nINR 199.00')),
      const SizedBox(height:20),FilledButton(onPressed:busy?null:()async {
        final draft=ReceiptDraft.parse(text.text);int amount=0;try{amount=parseMoney(draft.amount);}catch(_){}
        await Navigator.push(context,MaterialPageRoute<bool>(builder:(_)=>ItemEditor(controller:widget.controller,kind:Kind.subscription,
          draft:Item(id:const Uuid().v4(),kind:Kind.subscription,title:draft.merchant,amount:amount,currency:draft.currency,cycle:'Monthly',
            attachmentName:name,extra:{'searchText':text.text}),initialFile:bytes)));
      },child:const Text('Review draft')),
      const SizedBox(height:12),const Text('Confirm merchant, amount, billing cycle and next due date. Payment receipts do not prove recurring billing.'),
    ]))));
}
