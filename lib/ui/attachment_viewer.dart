import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'common.dart';

class AttachmentViewer extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  final Future<void> Function() export;
  const AttachmentViewer({super.key, required this.name, required this.bytes, required this.export});
  @override
  Widget build(BuildContext context) {
    final extension = name.split('.').last.toLowerCase();
    Widget content;
    if (extension == 'pdf') {
      content = PdfViewer.data(bytes, sourceName: name);
    } else if (['png','jpg','jpeg','webp','gif','bmp'].contains(extension)) {
      content = Center(child: InteractiveViewer(minScale: .5, maxScale: 8,
        child: Image.memory(bytes, errorBuilder: (_, __, ___) => const Text('This image could not be decoded.'))));
    } else if (['txt','md','csv','json','log','yaml','yml'].contains(extension)) {
      final truncated = bytes.length > 512 * 1024;
      content = SingleChildScrollView(padding: const EdgeInsets.all(24), child: SelectableText(
        utf8.decode(truncated ? bytes.sublist(0,512 * 1024) : bytes, allowMalformed: true) +
        (truncated ? '\n\nPreview limited to 512 KB. Export to read the entire file.' : ''),
        style: const TextStyle(fontSize: 15, height: 1.6)));
    } else {
      content = Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, size: 64),
          const SizedBox(height: 16), Text(name), const SizedBox(height: 12),
          const Text('This format needs an external application. Export a copy to open it.', textAlign: TextAlign.center),
          const SizedBox(height: 16), FilledButton.icon(onPressed: () => exportFile(context),
            icon: const Icon(Icons.save_alt), label: const Text('Export file'))])));
    }
    return Scaffold(appBar: AppBar(title: Text(name), actions: [IconButton(
      tooltip: 'Export unencrypted copy', icon: const Icon(Icons.save_alt),
      onPressed: () => exportFile(context))]), body: content);
  }
  Future<void> exportFile(BuildContext context) async {
    if (await confirm(context, 'Export a copy?', 'The exported copy is not encrypted by Safe Vault.', action: 'Export') && context.mounted) {
      await attempt(context, export);
    }
  }
}
