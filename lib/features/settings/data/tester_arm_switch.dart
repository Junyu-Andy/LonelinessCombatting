/// Tester arm switch — the 測試員工具 block 「切換組別（只限測試員帳號）」.
///
/// Calls the `setTesterArm` Cloud Function (functions/tester_arm.js), which
/// only accepts an account whose `users/{uid}.isTester` is true and only
/// while `app_config/feature_flags.testerArmSwitchEnabled` is on.  The
/// server writes the arm (the rules never let the client do it); the App
/// then re-reads the profile so [Arm.of] and every [ArmGate] follow at
/// once.  Participants never see the block and the server refuses them.
library;

import 'package:cloud_functions/cloud_functions.dart';

/// The one server call, behind an interface so widget tests use a fake.
abstract class TesterArmBackend {
  /// Switch the signed-in tester's own arm to [arm] ('A' or 'B').
  /// Throws [TesterArmException] with a readable reason on failure.
  Future<void> setArm(String arm);
}

class TesterArmException implements Exception {
  const TesterArmException(this.reason);

  /// Shown to the tester as-is (researcher / tester text only).
  final String reason;

  @override
  String toString() => reason;
}

class CloudTesterArmBackend implements TesterArmBackend {
  const CloudTesterArmBackend();

  @override
  Future<void> setArm(String arm) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('setTesterArm')
          .call(<String, dynamic>{'arm': arm});
    } on FirebaseFunctionsException catch (e) {
      throw TesterArmException(describeTesterArmError(e.code, e.message));
    } catch (e) {
      throw TesterArmException('切換失敗：$e');
    }
  }
}

/// Error code from `setTesterArm` → the line shown under the buttons.
String describeTesterArmError(String code, String? message) {
  switch (code) {
    case 'permission-denied':
      return '呢個帳號唔係測試員帳號（isTester），伺服器拒絕切換。';
    case 'failed-precondition':
      return '伺服器開關 testerArmSwitchEnabled 未開，暫時切換唔到。';
    case 'unauthenticated':
      return '請先登入。';
    case 'invalid-argument':
      return '組別參數唔啱（只可以係 A 或 B）。';
    default:
      return '切換失敗：$code ${message ?? ''}'.trim();
  }
}
