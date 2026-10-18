import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

@immutable
class SemanticRemoteModel extends Equatable {
  final Uri uri;
  final String fileName;
  final int? size;
  final String? sha256;

  @override
  List<Object?> get props => [uri, fileName, size, sha256];

  const new({
    required this.uri,
    required this.fileName,
    required this.size,
    required this.sha256,
  });
}

@immutable
class SemanticInstalledModel extends Equatable {
  final String path;
  final String id;

  @override
  List<Object?> get props => [path, id];

  const new({required this.path, required this.id});
}

@immutable
class SemanticDownloadProgress extends Equatable {
  final int received;
  final int? total;

  @override
  List<Object?> get props => [received, total];

  const new(this.received, this.total);

  double? get ratio => (total ?? 0) > 0 ? (received / total!).clamp(0, 1) : null;
}

class SemanticModelException implements Exception {
  final String message;

  const new(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class SemanticDownloadCancelledException extends SemanticModelException {
  const new() : super('download cancelled');
}

class SemanticDownloadCancelToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listeners.forEach((listener) => listener());
  }

  void _addListener(VoidCallback listener) => _listeners.add(listener);
}

// downloads, imports and verifies the embedding model file,
// stored in a private app directory
class SemanticModelManager {
  // EmbeddingGemma 2, text + vision encoders, for LiteRT-LM
  static const defaultRepository = 'litert-community/embeddinggemma-2-text-vision-440m-litert-lm';
  static const modelExtension = '.litertlm';
  static const _modelBaseName = 'model';
  static const _partialSuffix = '.part';
  static const _importSuffix = '.import';

  final Future<Directory> Function() baseDirectory;
  final http.Client Function() clientFactory;
  final String repository;

  new({
    required this.baseDirectory,
    required this.clientFactory,
    this.repository = defaultRepository,
  });

  Future<Directory> get _modelDirectory async {
    final dir = Directory(p.join((await baseDirectory()).path, 'semantic'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _modelFile async => File(p.join((await _modelDirectory).path, '$_modelBaseName$modelExtension'));

  Future<File> get _partialFile async => File('${(await _modelFile).path}$_partialSuffix');

  Future<File> get _importFile async => File('${(await _modelFile).path}$_importSuffix');

  // the Hugging Face API lists repository files, with LFS size and hash
  Future<SemanticRemoteModel> fetchRemoteModel() async {
    final client = clientFactory();
    try {
      final apiUri = Uri.https('huggingface.co', '/api/models/$repository', {'blobs': 'true'});
      final response = await client.get(apiUri);
      if (response.statusCode != 200) {
        throw SemanticModelException('failed to get model info from $apiUri with status=${response.statusCode}');
      }
      final json = jsonDecode(response.body);
      final siblings = json is Map ? json['siblings'] : null;
      if (siblings is! List) throw SemanticModelException('no files listed for repository=$repository');

      final candidates = siblings.whereType<Map>().where((v) => (v['rfilename'] as String?)?.endsWith(modelExtension) ?? false).toList();
      if (candidates.isEmpty) throw SemanticModelException('no `$modelExtension` file in repository=$repository');

      final file = candidates.first;
      final fileName = file['rfilename'] as String;
      final lfs = file['lfs'];
      return SemanticRemoteModel(
        uri: Uri.https('huggingface.co', '/$repository/resolve/main/$fileName'),
        fileName: fileName,
        size: (lfs is Map ? lfs['size'] : null) as int? ?? file['size'] as int?,
        sha256: lfs is Map ? lfs['sha256'] as String? : null,
      );
    } finally {
      client.close();
    }
  }

  // resumes a previous partial download when possible
  Future<SemanticInstalledModel> download(
    SemanticRemoteModel remote, {
    ValueChanged<SemanticDownloadProgress>? onProgress,
    SemanticDownloadCancelToken? cancelToken,
  }) async {
    final partialFile = await _partialFile;
    var received = await partialFile.exists() ? await partialFile.length() : 0;
    final expectedSize = remote.size;
    if (expectedSize != null && received > expectedSize) {
      await partialFile.delete();
      received = 0;
    }

    if (expectedSize == null || received < expectedSize) {
      received = await _downloadToPartialFile(remote, partialFile, received, onProgress, cancelToken);
    }

    if (expectedSize != null && received != expectedSize) {
      throw SemanticModelException('downloaded size=$received does not match expected size=$expectedSize');
    }

    final hash = await computeSha256(partialFile);
    if (remote.sha256 != null && remote.sha256 != hash) {
      await partialFile.delete();
      throw const SemanticModelException('downloaded file hash does not match expected hash');
    }
    return _install(partialFile, hash);
  }

  Future<int> _downloadToPartialFile(
    SemanticRemoteModel remote,
    File partialFile,
    int offset,
    ValueChanged<SemanticDownloadProgress>? onProgress,
    SemanticDownloadCancelToken? cancelToken,
  ) async {
    final client = clientFactory();
    cancelToken?._addListener(client.close);
    try {
      final request = http.Request('GET', remote.uri);
      if (offset > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';
      }
      final response = await client.send(request);
      if (response.statusCode == 200) {
        // range not honoured, restart from scratch
        offset = 0;
      } else if (response.statusCode != 206) {
        throw SemanticModelException('failed to download ${remote.uri} with status=${response.statusCode}');
      }

      final total = remote.size ?? (response.contentLength != null ? offset + response.contentLength! : null);
      final sink = partialFile.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      var received = offset;
      try {
        await for (final chunk in response.stream) {
          if (cancelToken?.isCancelled ?? false) throw const SemanticDownloadCancelledException();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(SemanticDownloadProgress(received, total));
        }
      } finally {
        await sink.close();
      }
      return received;
    } on http.ClientException catch (error) {
      if (cancelToken?.isCancelled ?? false) throw const SemanticDownloadCancelledException();
      throw SemanticModelException('download failed: ${error.message}');
    } finally {
      client.close();
    }
  }

  // `copyTo`: copies the selected file to the given path, returning whether a file was copied
  Future<SemanticInstalledModel?> import(Future<bool> Function(String destinationPath) copyTo) async {
    final importFile = await _importFile;
    if (await importFile.exists()) {
      await importFile.delete();
    }
    final copied = await copyTo(importFile.path);
    if (!copied || !await importFile.exists() || await importFile.length() == 0) {
      if (await importFile.exists()) {
        await importFile.delete();
      }
      return null;
    }
    return _install(importFile, await computeSha256(importFile));
  }

  Future<SemanticInstalledModel> _install(File source, String hash) async {
    final modelFile = await _modelFile;
    if (await modelFile.exists()) {
      await modelFile.delete();
    }
    final installed = await source.rename(modelFile.path);
    return SemanticInstalledModel(path: installed.path, id: modelIdFromHash(hash));
  }

  Future<bool> hasPartialDownload() async => (await _partialFile).exists();

  Future<void> delete() async {
    final dir = await _modelDirectory;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static String modelIdFromHash(String hash) => hash.substring(0, 16);

  static Future<String> computeSha256(File file) {
    final path = file.path;
    return Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
  }
}
