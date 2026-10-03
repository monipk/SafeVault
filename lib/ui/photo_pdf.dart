import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';
import '../core/controller.dart';
import '../core/model.dart';
import 'common.dart';
import 'editor.dart';

class PhotoPdf extends StatefulWidget {
  final VaultController controller;
  const PhotoPdf({super.key,required this.controller});
  @override State<PhotoPdf> createState()=>_PhotoPdfState();
}
class _PhotoPdfState extends State<PhotoPdf> {
  final pages=<Uint8List>[];bool busy=false;
  Future<void> add() async {
    if(busy)return;setState(()=>busy=true);
    await attempt(context,()async {
      final f=await widget.controller.files.pick();if(f==null)return;
      if(!RegExp(r'\.(png|jpe?g|webp)$',caseSensitive:false).hasMatch(f.name))throw const FormatException('Choose a JPG, PNG or WebP photo.');
      if(!mounted)return;
      final bytes=await Navigator.push<Uint8List>(context,MaterialPageRoute(builder:(_)=>PhotoCrop(bytes:f.bytes)));
      if(bytes!=null&&mounted)setState(()=>pages.add(bytes));
    });
    if(mounted)setState(()=>busy=false);
  }
  Future<void> create() async {
    if(busy||pages.isEmpty)return;setState(()=>busy=true);
    await attempt(context,()async {
      final pdf=pw.Document();
      for(final bytes in pages) pdf.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(_)=>pw.Center(child:pw.Image(pw.MemoryImage(bytes),fit:pw.BoxFit.contain))));
      final bytes=await pdf.save();
      if(bytes.length>10*1024*1024)throw const FormatException('PDF exceeds 10 MB. Use fewer pages.');
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute<bool>(builder:(_)=>ItemEditor(controller:widget.controller,kind:Kind.document,
        draft:Item(id:const Uuid().v4(),kind:Kind.document,title:'Scanned document',attachmentName:'scan.pdf'),initialFile:bytes)));
    });
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Photo to PDF')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Take photos using your camera, then select and crop them here. Up to 8 pages. This tool does not perform automatic edge detection or OCR.'),
      const SizedBox(height:16),if(busy)const LinearProgressIndicator(),
      for(var n=0;n<pages.length;n++) ListTile(leading:Image.memory(pages[n],width:48,height:64,fit:BoxFit.cover),title:Text('Page ${n+1}'),
        trailing:IconButton(tooltip:'Remove page',onPressed:busy?null:()=>setState(()=>pages.removeAt(n)),icon:const Icon(Icons.delete_outline))),
      if(pages.length<8)OutlinedButton.icon(onPressed:busy?null:add,icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('Add photo')),
      const SizedBox(height:16),FilledButton(onPressed:busy||pages.isEmpty?null:create,child:const Text('Create PDF')),
    ]))));
}
class PhotoCrop extends StatefulWidget {
  final Uint8List bytes;const PhotoCrop({super.key,required this.bytes});
  @override State<PhotoCrop> createState()=>_PhotoCropState();
}
class _PhotoCropState extends State<PhotoCrop> {
  ui.Image? preview;
  @override void initState(){super.initState();loadPreview();}
  Future<void> loadPreview()async{
    try{final codec=await ui.instantiateImageCodec(widget.bytes,targetWidth:1000,allowUpscaling:false);
      final frame=await codec.getNextFrame();codec.dispose();
      if(mounted){setState(()=>preview=frame.image);}else{frame.image.dispose();}
    }catch(_){}
  }
  @override void dispose(){preview?.dispose();super.dispose();}
  RangeValues horizontal=const RangeValues(0,1),vertical=const RangeValues(0,1);bool busy=false;
  Future<void> crop() async {
    if(busy)return;setState(()=>busy=true);
    await attempt(context,()async {
      final codec=await ui.instantiateImageCodec(widget.bytes,targetWidth:1800,allowUpscaling:false);
      final frame=await codec.getNextFrame();codec.dispose();final source=frame.image;
      try {
        final rect=Rect.fromLTRB(horizontal.start*source.width,vertical.start*source.height,horizontal.end*source.width,vertical.end*source.height);
        final width=rect.width.round().clamp(1,1800).toInt(),height=rect.height.round().clamp(1,10000).toInt();
        final recorder=ui.PictureRecorder();final canvas=Canvas(recorder);
        canvas.drawImageRect(source,rect,Rect.fromLTWH(0,0,width.toDouble(),height.toDouble()),Paint());
        final picture=recorder.endRecording();final image=await picture.toImage(width,height);picture.dispose();
        try {
          final data=await image.toByteData(format:ui.ImageByteFormat.png);
          if(data==null)throw const FormatException('Could not crop photo.');
          if(mounted)Navigator.pop(context,data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes));
        } finally { image.dispose(); }
      } finally { source.dispose(); }
    });
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Crop photo')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      SizedBox(height:320,child:preview==null?const Center(child:CircularProgressIndicator()):Center(child:AspectRatio(
        aspectRatio:preview!.width/preview!.height,child:CustomPaint(foregroundPainter:CropOutline(horizontal,vertical),child:RawImage(image:preview,fit:BoxFit.fill))))),
      const Text('Keep horizontal range'),RangeSlider(values:horizontal,onChanged:busy?null:(v){if(v.end-v.start>=.05)setState(()=>horizontal=v);}),
      const Text('Keep vertical range'),RangeSlider(values:vertical,onChanged:busy?null:(v){if(v.end-v.start>=.05)setState(()=>vertical=v);}),
      Text('Keep ${(horizontal.start*100).round()}–${(horizontal.end*100).round()}% width, ${(vertical.start*100).round()}–${(vertical.end*100).round()}% height'),
      const SizedBox(height:12),const Text('The outlined area is kept. Preview the PDF before saving.'),
      FilledButton(onPressed:busy?null:crop,child:Text(busy?'Cropping…':'Use crop')),
    ]));
}

class CropOutline extends CustomPainter {
  final RangeValues x,y;
  CropOutline(this.x,this.y);
  @override void paint(Canvas canvas,Size size){
    final rect=Rect.fromLTRB(x.start*size.width,y.start*size.height,x.end*size.width,y.end*size.height);
    final mask=Path()..addRect(Offset.zero & size)..addRect(rect)..fillType=PathFillType.evenOdd;
    canvas.drawPath(mask,Paint()..color=Colors.black.withValues(alpha:.45));
    canvas.drawRect(rect,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=2);
  }
  @override bool shouldRepaint(CropOutline old)=>old.x!=x||old.y!=y;
}
