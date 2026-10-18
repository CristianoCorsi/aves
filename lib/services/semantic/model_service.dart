import 'dart:async';
import 'dart:io';

import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/semantic/model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum SemanticModelStatus { absent, downloading, verifying, installed }

final SemanticModelService semanticModels = SemanticModelService._private();

// app level model management, keeping settings in sync with the installed model
class SemanticModelService {
  final SemanticModelManager _manager = SemanticModelManager(
    baseDirectory: getApplicationSupportDirectory,
    clientFactory: http.Client.new,
  );
  final ValueNotifier<SemanticModelStatus> statusNotifier = ValueNotifier(SemanticModelStatus.absent);
  final ValueNotifier<SemanticDownloadProgress?> progressNotifier = ValueNotifier(null);
  SemanticDownloadCancelToken? _cancelToken;

  new _private();

  void refreshStatus() {
    if (statusNotifier.value == SemanticModelStatus.downloading || statusNotifier.value == SemanticModelStatus.verifying) return;
    statusNotifier.value = isInstalled ? SemanticModelStatus.installed : SemanticModelStatus.absent;
  }

  bool get isInstalled {
    final path = settings.semanticModelPath;
    return path != null && settings.semanticModelId != null && File(path).existsSync();
  }

  bool get isBusy => statusNotifier.value == SemanticModelStatus.downloading || statusNotifier.value == SemanticModelStatus.verifying;

  Future<bool> get hasPartialDownload => _manager.hasPartialDownload();

  // throws `SemanticModelException` on failure
  Future<void> download() async {
    if (isBusy) return;
    if (settings.semanticDownloadWifiOnly && !await availability.isOnUnmeteredNetwork) {
      throw const SemanticNoUnmeteredNetworkException();
    }

    final cancelToken = SemanticDownloadCancelToken();
    _cancelToken = cancelToken;
    statusNotifier.value = SemanticModelStatus.downloading;
    progressNotifier.value = null;
    try {
      final remote = await _manager.fetchRemoteModel();
      await semanticEngine.unload();
      final installed = await _manager.download(
        remote,
        cancelToken: cancelToken,
        onProgress: (progress) {
          progressNotifier.value = progress;
          final total = progress.total;
          if (total != null && progress.received >= total) {
            statusNotifier.value = SemanticModelStatus.verifying;
          }
        },
      );
      _setInstalled(installed);
    } finally {
      _cancelToken = null;
      progressNotifier.value = null;
      statusNotifier.value = SemanticModelStatus.absent;
      refreshStatus();
    }
  }

  void cancelDownload() => _cancelToken?.cancel();

  // returns whether a model was imported
  Future<bool> import() async {
    if (isBusy) return false;
    statusNotifier.value = SemanticModelStatus.verifying;
    try {
      await semanticEngine.unload();
      final installed = await _manager.import(storageService.openFileTo);
      if (installed == null) return false;
      _setInstalled(installed);
      return true;
    } finally {
      statusNotifier.value = SemanticModelStatus.absent;
      refreshStatus();
    }
  }

  // also removes all semantic data, as it is tied to the model
  Future<void> delete() async {
    cancelDownload();
    await semanticEngine.unload();
    await _manager.delete();
    settings.semanticModelPath = null;
    settings.semanticModelId = null;
    await localMediaDb.clearSemanticData();
    refreshStatus();
  }

  void _setInstalled(SemanticInstalledModel installed) {
    debugPrint('$runtimeType installed model id=${installed.id} at path=${installed.path}');
    settings.semanticModelPath = installed.path;
    settings.semanticModelId = installed.id;
  }
}
