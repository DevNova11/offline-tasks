import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/local_store.dart';

/// Tracks whether the device has a network, plus a user-controlled
/// "work offline" switch that makes demoing offline behaviour easy without
/// touching airplane mode.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService(this._store, {Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final LocalStore _store;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _hasNetwork = false;
  bool get hasNetwork => _hasNetwork;
  bool get forcedOffline => _store.forcedOffline;
  bool get isOnline => _hasNetwork && !forcedOffline;

  Future<void> start() async {
    _update(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    final has = results.any((r) => r != ConnectivityResult.none);
    if (has == _hasNetwork) return;
    _hasNetwork = has;
    notifyListeners();
  }

  Future<void> setForcedOffline(bool v) async {
    await _store.setForcedOffline(v);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
