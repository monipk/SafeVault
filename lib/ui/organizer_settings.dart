import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'common.dart';
import 'design.dart';
import 'item_tools.dart';

class OrganizerSettings extends StatefulWidget {
  final VaultController controller;
  const OrganizerSettings({super.key,required this.controller});
  @override State<OrganizerSettings> createState()=>_OrganizerSettingsState();
}
class _OrganizerSettingsState extends State<OrganizerSettings> {
  bool busy=false;
  Future<void> change(String key,String value)async{
    if(busy)return;setState(()=>busy=true);await attempt(context,()=>widget.controller.setting(key,value));
    if(mounted)setState(()=>busy=false);
  }
  Future<void> folder()async{
    final text=TextEditingController();final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('New folder'),content:TextField(controller:text,maxLength:40,decoration:const InputDecoration(labelText:'Name')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,text.text.trim()),child:const Text('Add'))]));
    await Future<void>.delayed(const Duration(milliseconds:300));text.dispose();
    if(value!=null&&value.isNotEmpty&&!widget.controller.folders.any((v)=>v.toLowerCase()==value.toLowerCase())) {
      await change('folders',jsonEncode([...widget.controller.folders,value]));
    }
  }
  Future<void> quietTime(String key,int minutes)async{
    final at=await showTimePicker(context:context,initialTime:TimeOfDay(hour:minutes~/60,minute:minutes%60));
    if(at!=null)await change(key,'${at.hour*60+at.minute}');
  }
  @override Widget build(BuildContext context){final c=widget.controller;return ListenableBuilder(listenable:c,builder:(context,_)=>Scaffold(
    appBar:AppBar(title:const Text('Personalize')),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),
      child:AbsorbPointer(absorbing:busy,child:ListView(padding:const EdgeInsets.all(20),children:[
        if(busy)const LinearProgressIndicator(),
        VaultCard(child:ExpansionTile(title:const Text('Folders'),children:[
          for(final f in c.folders) ListTile(leading:const Icon(Icons.folder_outlined),title:Text(f)),
          TextButton.icon(onPressed:folder,icon:const Icon(Icons.add),label:const Text('New folder')),
        ])),
        VaultCard(child:ExpansionTile(title:const Text('Visible tabs'),children:[
          for(var n=1;n<5;n++)CheckboxListTile(title:Text(['Home','Doc','Sub','Notes','Plan'][n]),value:c.visibleTabs.contains(n),onChanged:(v){
            final tabs=<int>{0,...c.visibleTabs};v==true?tabs.add(n):tabs.remove(n);
            if(tabs.length<2){toast(context,'Keep Home and at least one other tab.');return;}
            change('visibleTabs',jsonEncode(tabs.toList()..sort()));
          }),const Padding(padding:EdgeInsets.all(16),child:Text('Hidden tabs do not delete records. Search still finds every item.')),
        ])),
        VaultCard(child:ExpansionTile(title:const Text('Home cards'),children:[
          for(final key in ['summary','spending'])CheckboxListTile(title:Text(key=='summary'?'Summary':'Spending'),value:c.dashboard.contains(key),
            onChanged:(v)=>change('dashboard',jsonEncode(v==true?[...c.dashboard,key]:c.dashboard.where((k)=>k!=key).toList()))),
          TextButton(onPressed:()=>change('dashboard',jsonEncode(c.dashboard.reversed.toList())),child:const Text('Reverse card order')),
        ])),
        VaultCard(child:ExpansionTile(title:const Text('Reading & contrast'),children:[
          ListTile(title:const Text('Text size'),subtitle:Text('${(c.textSize*100).round()}%')),
          Slider(min:1,max:1.5,divisions:5,value:c.textSize.clamp(1,1.5).toDouble(),label:'${(c.textSize*100).round()}%',onChanged:(v)=>change('textSize','$v')),
          SwitchListTile(title:const Text('High contrast'),value:c.contrast,onChanged:(v)=>change('contrast','$v')),
        ])),
        VaultCard(child:ExpansionTile(title:const Text('Quiet hours'),children:[
          SwitchListTile(title:const Text('Postpone alerts'),value:c.quiet,onChanged:(v)=>change('quiet','$v')),
          ListTile(title:const Text('From'),trailing:Text(TimeOfDay(hour:c.quietStart~/60,minute:c.quietStart%60).format(context)),onTap:()=>quietTime('quietStart',c.quietStart)),
          ListTile(title:const Text('Until'),trailing:Text(TimeOfDay(hour:c.quietEnd~/60,minute:c.quietEnd%60).format(context)),onTap:()=>quietTime('quietEnd',c.quietEnd)),
          const Padding(padding:EdgeInsets.all(16),child:Text('Alerts inside this period move to its end. Equal start and end disables postponement. This can delay deadline alerts.')),
        ])),
      ]))))));}
}

class StorageScreen extends StatefulWidget {
  final VaultController controller;const StorageScreen({super.key,required this.controller});
  @override State<StorageScreen> createState()=>_StorageScreenState();
}
class _StorageScreenState extends State<StorageScreen>{
  late Future<List<({String owner,String name,int size,String? asset})>> future=load();
  Future<List<({String owner,String name,int size,String? asset})>> load()async{
    final c=widget.controller;final result=<({String owner,String name,int size,String? asset})>[];
    for(final a in await c.repo.assets())result.add((owner:a.owner,name:'${a.name}${a.historical?' (older version)':''}',size:a.bytes.length,asset:a.id));
    for(final i in (await c.repo.all()).where((i)=>i.attachmentName.isNotEmpty)){
      final bytes=await c.repo.attachment(i.id);if(bytes!=null)result.add((owner:i.id,name:i.attachmentName,size:bytes.length,asset:null));}
    result.sort((a,b)=>b.size.compareTo(a.size));return result;
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Storage')),
    body:FutureBuilder(future:future,builder:(context,snapshot){
      if(!snapshot.hasData)return Center(child:snapshot.hasError?const Text('Could not read storage'):const CircularProgressIndicator());
      final files=snapshot.data!;final total=files.fold<int>(0,(n,f)=>n+f.size);
      return ListView(padding:const EdgeInsets.all(20),children:[Text('${(total/1024/1024).toStringAsFixed(1)} MB · ${files.length} files',style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:16),const Text('Files are listed largest first. Open an item to manage files and versions.'),
        for(final f in files)VaultCard(child:ListTile(title:Text(f.name),subtitle:Text('${(f.size/1024).ceil()} KB'),trailing:const Icon(Icons.chevron_right),
          onTap:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FileManager(controller:widget.controller,owner:f.owner)));
            if(mounted)setState(()=>future=load());})),
      ]);
    }));
}
