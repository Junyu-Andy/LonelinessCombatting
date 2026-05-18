/// B.7 — writes distress detections to the global `safety_events` collection
/// so the CF onCreate trigger can dedup and alert PI.
///
/// This class is the single write-point for all three sources defined in the
/// sprint plan: `gateway_input`, `gateway_output`, and `m3_turn`.  Arm B
/// callers use the same writer — safety checks are arm-invariant by design.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'distress_detector.dart';

/// One of the three paths that can write a safety event.
enum SafetySource {
  gatewayInput('gateway_input'),
  gatewayOutput('gateway_output'),
  m3Turn('m3_turn');

  const SafetySource(this.code);
  final String code;
}

class SafetyEventWriter {
  SafetyEventWriter({required this.available});

  final bool available;

  /// Write a safety event for [match] when its level is at least [moderate].
  ///
  /// [textHash] is the SHA-256 of the matched text (or the full input if no
  /// specific term was isolated).  Pre-hashing on the client keeps PII out of
  /// Firestore rule comparisons and limits what the client writes to hashes.
  ///
  /// The CF trigger computes the minute-bucket dedup server-side, so no clock
  /// synchronisation is required here.
  Future<void> maybeWrite({
    required String uid,
    required SafetySource source,
    required DistressMatch match,
    required String inputText,
    String? agentId,
    String? sessionId,
  }) async {
    if (!available) return;
    if (match.level == DistressLevel.none || match.level == DistressLevel.low) {
      return;
    }

    final textHash = _sha256(inputText);

    try {
      await FirebaseFirestore.instance.collection('safety_events').add({
        'uid': uid,
        'source': source.code,
        'textHash': textHash,
        'level': match.level.name,
        'matchedTerm': match.matchedTerm,
        'agentId': agentId,
        'sessionId': sessionId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[safety_event] write failed: $e');
    }
  }

  static String _sha256(String text) {
    final bytes = utf8.encode(text);
    return sha256.convert(bytes).toString();
  }
}
