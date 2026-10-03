import 'dart:convert';
import 'dart:typed_data';
class VaultAsset {
  final String id, owner, name, hash, group;
  final Uint8List bytes;
  final DateTime created;
  final bool historical;
  VaultAsset({required this.id, required this.owner, required this.name, required this.bytes,
    required this.hash, required this.created, required this.group, this.historical = false});
  VaultAsset asHistory() => VaultAsset(id: id, owner: owner, name: name, bytes: bytes,
    hash: hash, created: created, group: group, historical: true);
  Map<String,dynamic> toJson() => {'id':id,'owner':owner,'name':name,'bytes':base64Encode(bytes),
    'hash':hash,'created':created.toUtc().toIso8601String(),'group':group,'historical':historical};
  factory VaultAsset.fromJson(Map<String,dynamic> j) {
    final value = VaultAsset(id:j['id'] as String,owner:j['owner'] as String,name:j['name'] as String,
      bytes:base64Decode(j['bytes'] as String),hash:j['hash'] as String,created:DateTime.parse(j['created'] as String),
      group:j['group'] as String,historical:j['historical'] as bool);
    if (value.id.isEmpty || value.owner.isEmpty || value.name.length > 500 || value.bytes.length > 10*1024*1024) {
      throw const FormatException('Invalid attachment');
    }
    return value;
  }
}
