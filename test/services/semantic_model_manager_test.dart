import 'dart:convert';
import 'dart:io';

import 'package:aves/services/semantic/model_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  final modelBytes = utf8.encode('fake model content, long enough to be split in a few chunks');
  final modelHash = sha256.convert(modelBytes).toString();
  const repository = 'org/repo';

  setUp(() async => tempDir = await Directory.systemTemp.createTemp('aves_semantic_test'));
  tearDown(() async => tempDir.delete(recursive: true));

  http.Response apiResponse({String? hash}) => http.Response(
    jsonEncode({
      'siblings': [
        {'rfilename': 'README.md', 'size': 12},
        {
          'rfilename': 'embedder.litertlm',
          'size': modelBytes.length,
          'lfs': {'sha256': hash ?? modelHash, 'size': modelBytes.length},
        },
      ],
    }),
    200,
  );

  // serves the model, honouring `Range` requests when `supportRange` is true
  MockClient mockClient({bool supportRange = true, String? hash, List<String?>? rangeLog}) {
    return MockClient((request) async {
      if (request.url.path == '/api/models/$repository') return apiResponse(hash: hash);
      if (request.url.path == '/$repository/resolve/main/embedder.litertlm') {
        final range = request.headers[HttpHeaders.rangeHeader];
        rangeLog?.add(range);
        if (range != null && supportRange) {
          final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          return http.Response.bytes(modelBytes.sublist(start), 206);
        }
        return http.Response.bytes(modelBytes, 200);
      }
      return http.Response('not found', 404);
    });
  }

  SemanticModelManager buildManager(http.Client client) => SemanticModelManager(
    baseDirectory: () async => tempDir,
    clientFactory: () => client,
    repository: repository,
  );

  test('remote model info is read from repository listing', () async {
    final remote = await buildManager(mockClient()).fetchRemoteModel();
    expect(remote.fileName, 'embedder.litertlm');
    expect(remote.size, modelBytes.length);
    expect(remote.sha256, modelHash);
    expect(remote.uri.toString(), 'https://huggingface.co/$repository/resolve/main/embedder.litertlm');
  });

  test('download installs verified model', () async {
    final manager = buildManager(mockClient());
    final progress = <int>[];
    final installed = await manager.download(await manager.fetchRemoteModel(), onProgress: (v) => progress.add(v.received));
    expect(await File(installed.path).readAsBytes(), modelBytes);
    expect(installed.id, SemanticModelManager.modelIdFromHash(modelHash));
    expect(progress.last, modelBytes.length);
    expect(await manager.hasPartialDownload(), isFalse);
  });

  test('download resumes from partial file', () async {
    final rangeLog = <String?>[];
    final manager = buildManager(mockClient(rangeLog: rangeLog));
    final remote = await manager.fetchRemoteModel();
    final partial = File('${tempDir.path}/semantic/model.litertlm.part');
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(modelBytes.sublist(0, 10));

    final installed = await manager.download(remote);
    expect(rangeLog, ['bytes=10-']);
    expect(await File(installed.path).readAsBytes(), modelBytes);
  });

  test('download restarts when server ignores range', () async {
    final manager = buildManager(mockClient(supportRange: false));
    final remote = await manager.fetchRemoteModel();
    final partial = File('${tempDir.path}/semantic/model.litertlm.part');
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(modelBytes.sublist(0, 10));

    final installed = await manager.download(remote);
    expect(await File(installed.path).readAsBytes(), modelBytes);
  });

  test('download rejects hash mismatch', () async {
    final manager = buildManager(mockClient(hash: 'deadbeef'));
    final remote = await manager.fetchRemoteModel();
    await expectLater(manager.download(remote), throwsA(isA<SemanticModelException>()));
    expect(await manager.hasPartialDownload(), isFalse);
  });

  test('import installs copied file, or nothing when cancelled', () async {
    final manager = buildManager(mockClient());
    expect(await manager.import((_) async => false), isNull);

    final installed = await manager.import((path) async {
      await File(path).writeAsBytes(modelBytes);
      return true;
    });
    expect(installed!.id, SemanticModelManager.modelIdFromHash(modelHash));
    expect(await File(installed.path).readAsBytes(), modelBytes);

    await manager.delete();
    expect(await File(installed.path).exists(), isFalse);
  });
}
