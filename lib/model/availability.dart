import 'package:aves/model/device.dart';
import 'package:aves/model/semantic/profile.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/device_service.dart';
import 'package:aves_map/aves_map.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class AvesAvailability {
  Future<void> onNewIntent();

  void onResume();

  bool get isLocked;

  Future<bool> get isConnected;

  Future<bool> get canLocatePlaces;

  // connected via Wi-Fi or Ethernet, i.e. not on a metered mobile network
  Future<bool> get isOnUnmeteredNetwork;

  Future<bool> get canUseSemantic;

  List<EntryMapStyle> get mapStyles;
}

class LiveAvesAvailability implements AvesAvailability {
  bool? _isConnected, _isLocked, _canUseSemantic;
  List<ConnectivityResult> _connectivity = [];

  new() {
    Connectivity().onConnectivityChanged.listen(_updateConnectivityFromResult);
  }

  @override
  Future<void> onNewIntent() async {
    _isLocked = await deviceService.isLocked();
    debugPrint('Device is locked=$_isLocked');
  }

  @override
  void onResume() => _isConnected = null;

  @override
  bool get isLocked => _isLocked ?? false;

  @override
  Future<bool> get isConnected async {
    if (_isConnected != null) return SynchronousFuture(_isConnected!);
    final result = await (Connectivity().checkConnectivity());
    _updateConnectivityFromResult(result);
    return _isConnected!;
  }

  void _updateConnectivityFromResult(List<ConnectivityResult> result) {
    _connectivity = result;
    final newValue = result.isNotEmpty && !result.contains(ConnectivityResult.none);
    if (_isConnected != newValue) {
      _isConnected = newValue;
      debugPrint('Device is connected=$_isConnected');
    }
  }

  @override
  Future<bool> get canLocatePlaces async => device.hasGeocoder && await isConnected;

  @override
  Future<bool> get isOnUnmeteredNetwork async {
    if (!await isConnected) return false;
    return _connectivity.contains(ConnectivityResult.wifi) || _connectivity.contains(ConnectivityResult.ethernet);
  }

  @override
  Future<bool> get canUseSemantic async {
    if (_canUseSemantic != null) return SynchronousFuture(_canUseSemantic!);
    var canUse = semanticEngine.isSupported && !device.isTelevision;
    if (canUse) {
      final ram = await deviceService.getRamSizes({MemorySizeType.total});
      canUse = (ram[MemorySizeType.total] ?? 0) >= SemanticPerformanceParams.minRamBytes;
    }
    _canUseSemantic = canUse;
    return canUse;
  }

  @override
  List<EntryMapStyle> get mapStyles => [
    ...mobileServices.mapStyles,
    ...EntryMapStyles.baseStyles,
  ];
}
