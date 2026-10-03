import 'dart:io';

Future<void> main() async {
  if (!File('pubspec.lock').existsSync() || !Directory('web').existsSync()) {
    throw StateError('Run dart tool/setup.dart first.');
  }
  final lock = File('pubspec.lock').readAsStringSync();
  final version = RegExp(
    r'^  drift:\n[\s\S]*?    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock)?.group(1);
  if (version == null) {
    throw StateError('Cannot read Drift version from pubspec.lock');
  }
  final client = HttpClient();
  try {
    for (final name in ['sqlite3.wasm', 'drift_worker.js']) {
      final uri = Uri.parse(
        'https://github.com/simolus3/drift/releases/download/drift-$version/$name',
      );
      stdout.writeln('Downloading $name for Drift $version…');
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed (${response.statusCode}). Download matching assets from https://github.com/simolus3/drift/releases/tag/drift-$version into web/.',
          uri: uri,
        );
      }
      final temporary = File('web/$name.part');
      await response.pipe(temporary.openWrite());
      await temporary.rename('web/$name');
    }
  } finally {
    client.close();
  }
  stdout.writeln('Ready: flutter run -d chrome --web-port=7357');
}
