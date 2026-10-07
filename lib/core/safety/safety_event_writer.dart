/// B.7 — writes distress detections to the global `safety_events` collection
/// so the CF onCreate trigger can dedup and alert PI.
///
/// The single write-point for every surface in both arms.  Callers do not
/// use it directly any more: they go through [SafetyService] in
/// `safety_check.dart` (T7), which picks [SafetySource], the input point
/// and the turn id.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'distress_detector.dart';
import 'safety_classifier.dart';

/// `safety_events.source` — the three analysis buckets (T7, decision 0018).
///
/// Pre-T7 codes, still accepted by the rules for old builds:
/// `gateway_input` / `rule_turn` → [userInput]; `gateway_output` →
/// [aiOutputScan]; `m3_turn` was never written.
enum SafetySource {
  /// Something the participant typed or said in a conversation (chat,
  /// check-in note, reminiscence entry, search words) — both arms.
  userInput('user_input'),

  /// The deterministic scan of an AI reply (Hybrid arm only).
  aiOutputScan('ai_output_scan'),

  /// A free-text field in a form (Thought Exercise, intake, agent
  /// comparison, feedback, action plan, weekly questionnaire, edits).
  form('form');

  const SafetySource(this.code);
  final String code;
}

class SafetyEventWriter {
  SafetyEventWriter({required this.available});

  final bool available;

  /// Write a safety event for [match] when its level is at least moderate.
  ///
  /// [uid] may be null or empty: the signed-in user is used instead (before
  /// T7 seven AI calls passed no uid, so the rules silently rejected their
  /// events).  [turnId] ties every scan of one conversational turn together
  /// so the server counts the turn once.  [inputPoint] is the
  /// [SafetyInputPoint] code.
  ///
  /// [inputText] is hashed (SHA-256) on the client; the text itself is
  /// never written.
  ///
  /// T8: [detector] (`lexicon` / `classifier` / `both`) and the
  /// [classifier] fields are added only when the classifier path ran
  /// (switch on); with the switch off the doc is exactly as before.
  Future<void> maybeWrite({
    String? uid,
    required SafetySource source,
    required DistressMatch match,
    required String inputText,
    String? inputPoint,
    String? turnId,
    String? agentId,
    String? sessionId,
    String? detector,
    ClassifierVerdict? classifier,
  }) async {
    if (!available) return;
    if (!match.isEscalation) return;

    try {
      final resolvedUid = (uid != null && uid.isNotEmpty)
          ? uid
          : FirebaseAuth.instance.currentUser?.uid;
      if (resolvedUid == null || resolvedUid.isEmpty) {
        if (kDebugMode) debugPrint('[safety_event] no signed-in user; skipped');
        return;
      }
      await FirebaseFirestore.instance.collection('safety_events').add({
        'uid': resolvedUid,
        'source': source.code,
        'inputPoint': inputPoint,
        'turnId': turnId,
        'textHash': _sha256(inputText),
        // `level` keeps the legacy 4-band label the Firestore rule and CF
        // trigger validate against; `tier` carries the S-1 split.
        'level': match.level.legacyLevelCode,
        'tier': match.level.tierCode,
        'category': match.category?.code,
        'lexiconVersion': DistressDetector.wordlistVersion,
        'matchedTerm': match.matchedTerm,
        'agentId': agentId,
        'sessionId': sessionId,
        'createdAt': FieldValue.serverTimestamp(),
        if (detector != null) 'detector': detector,
        if (classifier != null) ...{
          'classifierStatus': classifier.status.code,
          'classifierLevel': classifier.level?.tierCode,
          'classifierScore': classifier.score,
          'classifierVersion': classifier.modelVersion,
        },
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
