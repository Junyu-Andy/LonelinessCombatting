import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper over connectivity_plus for the chat offline-resend queue.
///
/// Reports whether the device has *a network interface* (Wi-Fi / mobile) —
/// enough to detect airplane mode / no-signal, which is what strands a chat
/// message. It does not guarantee real internet reachability; the send itself
/// still handles a request that fails despite an interface being up.
class ConnectivityService {
  final Connectivity _c = Connectivity();

  /// True when at least one non-`none` interface is present.
  Future<bool> isOnline() async {
    try {
      return _online(await _c.checkConnectivity());
    } catch (_) {
      // On any error, assume online so we never wrongly block a send.
      return true;
    }
  }

  /// Emits the online/offline bool on every connectivity change.
  Stream<bool> get onStatusChange => _c.onConnectivityChanged.map(_online);

  static bool _online(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      results.any((r) => r != ConnectivityResult.none);
}
