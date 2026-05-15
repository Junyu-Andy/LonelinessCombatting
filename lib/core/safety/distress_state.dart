import 'package:flutter/foundation.dart';

import 'distress_detector.dart';

/// App-wide, observable distress level. Modules push the latest
/// [DistressMatch] here whenever they run a [DistressDetector] pass on
/// user input or LLM output, and [SafetyOverlay] listens to repaint the
/// pill's label + colour.
///
/// Kept distinct from [DistressDetector] (which is a pure, stateless
/// classifier) so the same classifier can run from many call sites
/// without each one carrying notifier wiring.
class DistressState extends ChangeNotifier {
  DistressMatch _current = const DistressMatch(DistressLevel.none);

  DistressMatch get current => _current;
  DistressLevel get level => _current.level;

  void report(DistressMatch match) {
    if (_current.level == match.level &&
        _current.matchedTerm == match.matchedTerm) {
      return;
    }
    _current = match;
    notifyListeners();
  }

  void reset() => report(const DistressMatch(DistressLevel.none));
}
