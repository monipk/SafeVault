import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/model.dart';
import '../core/assets.dart';
import 'common.dart';
import 'design.dart';
import 'attachment_viewer.dart';
import 'reminder_picker.dart';

Future<Item> currentItem(VaultController c, String id) async =>
  (await c.repo.all()).firstWhere((i) => i.id == id, orElse: () => throw const FormatException('Item no longer exists.'));

class FileManager extends StatefulWidget {
  final VaultController controller;
  final String owner;
  const FileManager({super.key, required this.controller, required this.owner});
  @override
  State<FileManager> createState() => _FileManagerState();
}
class _FileManagerState extends State<FileManager> {
  bool busy = false, history = false;
  late Future<({Item item, List<VaultAsset> files})> future = load();
  Future<({Item item,List<VaultAsset> files})> load() async =>
    (item: await currentItem(widget.controller,widget.owner), files: await widget.controller.repo.assets(owner:widget.owner));
  Future<void> run(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true); await attempt(context,f);
    if (mounted) setState(() { busy = false; future = load(); });
  }
  Future<void> add({String? replacing}) async {
    final c = widget.controller; final picked = await c.files.pick();
    if (picked == null) return;
    if (await c.repo.duplicate(picked.bytes)) {
      if (!mounted || !await confirm(context,'Duplicate file','This file is already stored. Add another copy?',action:'Add copy')) return;
    }
    await c.mutate(() => c.repo.addAsset(widget.owner,picked.name,picked.bytes,replaceId:replacing));
  }
  void view(String name, Uint8List bytes) => Navigator.push(context,MaterialPageRoute<void>(builder: (_) =>
    AttachmentViewer(name:name,bytes:bytes,export:() async { await widget.controller.files.save(name,bytes); })));
  @override
  Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Files'),actions:[
    IconButton(tooltip:'Add file',onPressed:busy?null:()=>run(()=>add()),icon:const Icon(Icons.attach_file))]),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:FutureBuilder(
      future:future,builder:(context,snapshot) {
        if (!snapshot.hasData) return Center(child:snapshot.hasError?const Text('Could not load files'):const CircularProgressIndicator());
        final data=snapshot.data!;
        return ListView(padding:const EdgeInsets.all(20),children:[
          if(busy) const LinearProgressIndicator(),
          FilledButton.icon(onPressed:busy?null:()=>run(()=>add()),icon:const Icon(Icons.add),label:const Text('Add file')),
          const SizedBox(height:16),
          if(data.item.attachmentName.isNotEmpty) VaultCard(child:ListTile(title:Text(data.item.attachmentName),subtitle:const Text('Original attachment'),
            trailing:IconButton(tooltip:'Delete original file',icon:const Icon(Icons.delete_outline),onPressed:busy?null:()=>run(()async{
              if(!await confirm(context,'Delete original file?','This copy is permanently removed. Other files and older versions stay.',action:'Delete'))return;
              final c=widget.controller;final latest=await currentItem(c,widget.owner);
              await c.mutate(()=>c.repo.save(latest.patch({'attachmentName':''}),removeAttachment:true,keepHistory:false));
            })),
            leading:const Icon(Icons.description_outlined),onTap:()=>run(() async {
              final bytes=await widget.controller.repo.attachment(widget.owner);
              if(bytes!=null && mounted) view(data.item.attachmentName,bytes);
            }))),
          SwitchListTile(title:const Text('Show older versions'),value:history,onChanged:(v)=>setState(()=>history=v)),
          for(final file in data.files.where((f)=>history || !f.historical)) VaultCard(child:ListTile(
            leading:Icon(file.historical?Icons.history:Icons.insert_drive_file_outlined),title:Text(file.name),
            subtitle:Text('${(file.bytes.length/1024).ceil()} KB · ${dateKey(file.created.toLocal())}${file.historical?' · older version':''}'),
            onTap:()=>view(file.name,file.bytes),trailing:PopupMenuButton<String>(enabled:!busy,onSelected:(v)=>run(() async {
              if(v=='replace') { await add(replacing:file.id); }
              else if(await confirm(context,'Delete file?','This copy will be permanently removed.',action:'Delete')) {
                await widget.controller.mutate(()=>widget.controller.repo.removeAsset(file.id));
              }
            }),itemBuilder:(_)=>[
              if(!file.historical) const PopupMenuItem(value:'replace',child:Text('Replace · keep version')),
              const PopupMenuItem(value:'delete',child:Text('Delete copy'))]))),
          if(data.files.isEmpty && data.item.attachmentName.isEmpty) const EmptyState(title:'No files yet',subtitle:'Attach receipts, images or documents.'),
          const Text('Up to 30 additional files and versions per item; 10 MB each. Replaced original files are retained in history.'),
        ]);
      }))));
}

class ItemOptions extends StatefulWidget {
  final VaultController controller;
  final Item item;
  const ItemOptions({super.key,required this.controller,required this.item});
  @override
  State<ItemOptions> createState()=>_ItemOptionsState();
}
class _ItemOptionsState extends State<ItemOptions> {
  late String folder=widget.item.folder;
  late Map<String,dynamic> extra={...widget.item.extra};
  late final contact=TextEditingController(text:extra['contact'] as String? ?? '');
  late final checklist=TextEditingController(text:((extra['checklist'] as List?)??[]).map((v)=>v['text']).join('\n'));
  late final searchText=TextEditingController(text:widget.item.searchText);
  late List<DateTime> alerts=widget.item.additionalReminders;
  bool busy=false;
  @override void dispose(){contact.dispose();checklist.dispose();searchText.dispose();super.dispose();}
  Future<void> date(String key,String label) async {
    final old=DateTime.tryParse(extra[key] as String? ?? '');
    final value=await showDatePicker(context:context,initialDate:old??DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime(2200));
    if(value!=null&&mounted) setState(()=>extra[key]=dateKey(value));
  }
  Future<void> alert() async {
    DateTime? selected=DateTime.now().add(const Duration(minutes:5));
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(
      title:const Text('Additional reminder'),content:SizedBox(width:440,child:SingleChildScrollView(child:ReminderPicker(enabled:true,selected:selected,
        onChanged:(_,at)=>setLocal(()=>selected=at)))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add'))])));
    if(ok==true&&selected!=null&&mounted) setState(()=>alerts.add(selected!));
  }
  Future<void> save() async {
    if(busy)return;setState(()=>busy=true);
    await attempt(context,() async {
      for(final at in alerts){
        if(!widget.item.additionalReminders.contains(at)&&!at.isAfter(DateTime.now()))throw const FormatException('Choose future times for new reminders.');
      }
      final c=widget.controller;final latest=await currentItem(c,widget.item.id);
      final previous=((latest.extra['checklist'] as List?)??[]);
      final lines=checklist.text.split('\n').map((v)=>v.trim()).where((v)=>v.isNotEmpty).take(50);
      await c.save(latest.withExtra({...extra,'folder':folder,'contact':contact.text,'searchText':searchText.text,
        'alerts':alerts.map((a)=>a.toUtc().toIso8601String()).toList(),
        'checklist':[for(final line in lines){'text':line,'done':previous.any((v)=>v['text']==line&&v['done']==true)}]}));
      if(mounted) Navigator.pop(context);
    });
    if(mounted)setState(()=>busy=false);
  }
  Widget dateRow(String key,String label)=>ListTile(title:Text(label),subtitle:Text(extra[key] as String? ?? 'Not set'),
    onTap:()=>date(key,label),trailing:IconButton(tooltip:'Clear',icon:const Icon(Icons.close),onPressed:()=>setState(()=>extra.remove(key))));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Organize')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:AbsorbPointer(absorbing:busy,child:ListView(
      padding:const EdgeInsets.all(20),children:[
        DropdownButtonFormField<String>(initialValue:folder,isExpanded:true,decoration:const InputDecoration(labelText:'Folder'),items:[
          for(final f in <String>{'',...widget.controller.folders,folder}) DropdownMenuItem(value:f,child:Text(f.isEmpty?'No folder':f))],onChanged:(v)=>setState(()=>folder=v!)),
        const SizedBox(height:20),
        VaultCard(child:ExpansionTile(title:const Text('Extra reminders'),subtitle:Text('${alerts.length} additional alerts'),children:[
          const Padding(padding:EdgeInsets.all(16),child:Text('Turn on the main Reminder switch in Edit to enable these alerts. Quiet hours can postpone them.')),
          for(final at in alerts) ListTile(title:Text('${dateKey(at)} · ${TimeOfDay.fromDateTime(at).format(context)}'),trailing:IconButton(
            tooltip:'Remove reminder',icon:const Icon(Icons.close),onPressed:()=>setState(()=>alerts.remove(at)))),
          if(alerts.length<8) TextButton.icon(onPressed:alert,icon:const Icon(Icons.add_alarm),label:const Text('Add reminder')),
        ])),
        if(widget.item.kind==Kind.subscription) VaultCard(child:ExpansionTile(title:const Text('Trial & cancellation'),children:[
          dateRow('trialEnd','Trial ends'),dateRow('cancelBy','Cancel before'),
          SwitchListTile(title:const Text('Cancellation confirmed'),value:extra['cancelledConfirmed']==true,
            onChanged:(v)=>setState(()=>extra['cancelledConfirmed']=v)),
          const Padding(padding:EdgeInsets.all(16),child:Text('Dates are tracked here. Add a reminder above for the date you want to be notified. Attach confirmation receipts in Files.')),
        ])),
        if(widget.item.kind==Kind.document) VaultCard(child:ExpansionTile(title:const Text('Warranty'),children:[
          dateRow('purchased','Purchased'),dateRow('warrantyEnd','Warranty ends'),
          Padding(padding:const EdgeInsets.all(16),child:TextField(controller:contact,decoration:const InputDecoration(labelText:'Service contact'))),
        ])),
        VaultCard(child:ExpansionTile(title:const Text('Renewal checklist'),children:[Padding(padding:const EdgeInsets.all(16),child:TextField(
          controller:checklist,minLines:3,maxLines:8,maxLength:4000,decoration:const InputDecoration(labelText:'One step per line')))])),
        VaultCard(child:ExpansionTile(title:const Text('Searchable document text'),children:[Padding(padding:const EdgeInsets.all(16),child:TextField(
          controller:searchText,minLines:3,maxLines:8,maxLength:60000,decoration:const InputDecoration(labelText:'Paste extracted text',helperText:'Included in vault search')))])),
        if((extra['prices'] as List?)?.isNotEmpty??false) VaultCard(child:ExpansionTile(title:const Text('Price history'),children:[
          for(final entry in (extra['prices'] as List).reversed) ListTile(title:Text('${money(entry['from'] as int,entry['currency'] as String)} → ${money(entry['to'] as int,entry['currency'] as String)}'),
            subtitle:Text((entry['date'] as String).split('T').first)),
        ])),
        FilledButton(onPressed:busy?null:save,child:Text(busy?'Saving…':'Save')),
      ])))));
}
