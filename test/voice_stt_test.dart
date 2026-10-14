// T27 — voice input via the server (SPEC:C18): WAV wrapper, failure
// categories, the S6 state next to the input box, the failure event, and
// the B03 stop-for-send path.  The microphone and the Cloud Function are
// fakes; nothing here touches a plugin.
import 'dart:async';
import 'dart:typed_data';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/voice/transcription_repository.dart';
import 'package:app_demo/core/voice/voice_copy.dart';
import 'package:app_demo/core/voice/voice_input_button.dart';
import 'package:app_demo/core/voice/voice_recorder.dart';
import 'package:app_demo/core/voice/wav_encoder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.permission = true, this.chunks = const []});

  final bool permission;
  final List<Uint8List> chunks;
  StreamController<Uint8List>? _ctrl;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    _ctrl = StreamController<Uint8List>();
    for (final c in chunks) {
      _ctrl!.add(c);
    }
    return _ctrl!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await _ctrl?.close();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await _ctrl?.close();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeClient implements TranscriptionClient {
  FakeClient(this.result);

  TranscriptionResult result;
  final List<Uint8List> received = [];

  @override
  Future<TranscriptionResult> transcribe(Uint8List wavBytes) async {
    received.add(wavBytes);
    return result;
  }
}

Uint8List _pcm(int n) => Uint8List.fromList(List.filled(n, 7));

void main() {
  late AnalyticsService analytics;

  Widget host({
    required ValueChanged<String> onText,
    String Function()? prefix,
    VoiceInputController? controller,
    Locale locale = const Locale('zh'),
  }) {
    analytics = AnalyticsService(firebaseReady: false);
    return AnalyticsScope(
      analytics: analytics,
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              Row(children: [
                VoiceInputButton(
                  onText: onText,
                  prefix: prefix,
                  controller: controller,
                ),
                const Expanded(child: TextField()),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUp(() {
    RemoteFeatureFlags.current = const RemoteFeatureFlags(voiceInputEnabled: true);
  });
  tearDown(() {
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
    VoiceInputButton.debugRecorderFactory = null;
    VoiceInputButton.debugTranscriptionClient = null;
  });

  group('WavEncoder', () {
    test('44-byte RIFF header, PCM16 mono 16 kHz', () {
      final wav = WavEncoder.fromPcm16(_pcm(32000),
          sampleRate: 16000, channels: 1);
      expect(wav.length, 44 + 32000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      final b = ByteData.sublistView(wav);
      expect(b.getUint32(4, Endian.little), 36 + 32000);
      expect(b.getUint16(20, Endian.little), 1); // PCM
      expect(b.getUint16(22, Endian.little), 1); // mono
      expect(b.getUint32(24, Endian.little), 16000);
      expect(b.getUint32(28, Endian.little), 32000); // byte rate
      expect(b.getUint16(32, Endian.little), 2); // block align
      expect(b.getUint16(34, Endian.little), 16);
      expect(b.getUint32(40, Endian.little), 32000);
      expect(wav[44], 7);
    });

    test('duration', () {
      expect(WavEncoder.durationMs(32000, sampleRate: 16000, channels: 1), 1000);
      expect(WavEncoder.durationMs(0, sampleRate: 16000, channels: 1), 0);
      // 60 s cap at this format stays far below the server's 10 MB limit.
      expect(WavEncoder.bytesPerSecond(sampleRate: 16000, channels: 1) * 60,
          lessThan(10 * 1024 * 1024));
    });
  });

  group('failure categories', () {
    test('server category wins; codes map when missing', () {
      String cat(String code, [Object? details]) =>
          TranscriptionFailure.fromFunctionsError(FirebaseFunctionsException(
              message: 'x', code: code, details: details));
      expect(cat('internal', {'category': 'no_speech', 'attempts': 1}),
          TranscriptionFailure.noSpeech);
      expect(cat('internal', {'category': 'bogus'}),
          TranscriptionFailure.serverError);
      expect(cat('deadline-exceeded'), TranscriptionFailure.timeout);
      expect(cat('unavailable'), TranscriptionFailure.unavailable);
      expect(cat('failed-precondition'), TranscriptionFailure.unavailable,
          reason: 'flag off on the server');
      expect(cat('not-found'), TranscriptionFailure.noSpeech);
      expect(cat('invalid-argument'), TranscriptionFailure.tooLong);
      expect(cat('internal'), TranscriptionFailure.serverError);
      expect(TranscriptionFailure.all, hasLength(5));
    });

    test('event payload carries category, session, companion, time only', () {
      final p = VoiceTranscriptionFailedEvent.payload(
          category: 'timeout', sessionId: 's1', agentId: 'tung_tung');
      expect(p.keys.toSet(), {'sessionId', 'agentId', 'category', 'at'});
      expect(VoiceTranscriptionFailedEvent.name, 'voice_transcription_failed');
    });

    test('S6 is the verbatim final text; English is a marked draft', () {
      expect(VoiceCopy.s6TranscriptionFailed,
          '頭先段錄音轉唔到做文字，唔係你嘅問題。你可以打字話我知，或者等陣再試下講。');
      expect(VoiceCopy.s6TranscriptionFailedEn, startsWith('【占位】'));
    });
  });

  group('VoiceInputButton', () {
    testWidgets('renders nothing and never touches the mic while off',
        (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final rec = FakeRecorder();
      VoiceInputButton.debugRecorderFactory = () => rec;
      await tester.pumpWidget(host(onText: (_) {}));
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
      expect(rec.starts, 0);
    });

    testWidgets('tap, tap: clip goes to the server as WAV, text lands in '
        'the field with the typed prefix kept', (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600), _pcm(1600)]);
      final client = FakeClient(const TranscriptionResult.ok('今日好開心'));
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient = client;
      String? got;
      await tester.pumpWidget(host(onText: (t) => got = t, prefix: () => '早晨'));
      await tester.pump();
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      await tapMic(tester);
      expect(rec.starts, 1);
      expect(find.byIcon(Icons.stop_circle_rounded), findsOneWidget);
      await tapMic(tester);
      await tester.pumpAndSettle();
      expect(rec.stops, 1);
      expect(client.received, hasLength(1));
      expect(client.received.single.length, 44 + 3200);
      expect(String.fromCharCodes(client.received.single.sublist(0, 4)),
          'RIFF');
      expect(got, '早晨 今日好開心');
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsNothing);
      expect(analytics.bufferedEvents, isEmpty);
    });

    testWidgets('failure: S6 verbatim next to the mic, not in a chat list; '
        'event logged with the category only', (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600)]);
      final client =
          FakeClient(const TranscriptionResult.failed('server_error'));
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient = client;
      String? got;
      await tester.pumpWidget(host(onText: (t) => got = t));
      await tester.pump();
      await tapMic(tester);
      await tapMic(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(got, isNull, reason: 'nothing written into the field');
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_s6_notice')), findsOneWidget);
      // Anchored above the mic (same left edge), i.e. by the input row.
      final mic = tester.getRect(find.byType(IconButton));
      final card = tester.getRect(find.byKey(const ValueKey('voice_s6_notice')));
      expect(card.bottom, lessThanOrEqualTo(mic.top));
      expect((card.left - mic.left).abs(), lessThan(1));
      // One event, category only; no text, no audio.
      final ev = analytics.bufferedEvents
          .where((e) => e['name'] == 'voice_transcription_failed')
          .toList();
      expect(ev, hasLength(1));
      final params = ev.single['params'] as Map;
      expect(params['category'], 'server_error');
      expect(params.keys.toSet(), {'sessionId', 'agentId', 'category', 'at'});
      expect(ev.single.toString(), isNot(contains('RIFF')));
      // Mic is usable again right away; the card goes when tapped.
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice_s6_notice')));
      await tester.pump();
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsNothing);
    });

    testWidgets('S6 card disappears on its own', (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600)]);
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient =
          FakeClient(const TranscriptionResult.failed('timeout'));
      await tester.pumpWidget(host(onText: (_) {}));
      await tester.pump();
      await tapMic(tester);
      await tapMic(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsOneWidget);
      await tester.pump(VoiceInputButton.noticeDuration +
          const Duration(seconds: 1));
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsNothing);
    });

    testWidgets('empty clip is a no_speech failure without a server call',
        (tester) async {
      final rec = FakeRecorder();
      final client = FakeClient(const TranscriptionResult.ok('x'));
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient = client;
      await tester.pumpWidget(host(onText: (_) {}));
      await tester.pump();
      await tapMic(tester);
      await tapMic(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.received, isEmpty);
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsOneWidget);
      final params = analytics.bufferedEvents.single['params'] as Map;
      expect(params['category'], 'no_speech');
    });

    testWidgets('controller routes the event into the session recorder',
        (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600)]);
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient =
          FakeClient(const TranscriptionResult.failed('unavailable'));
      final ctrl = VoiceInputController();
      final sessionAnalytics = AnalyticsService(firebaseReady: false);
      final recorder = ChatSessionRecorder(
        uid: null,
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        analytics: sessionAnalytics,
        available: false,
      );
      await recorder.ensureStarted();
      ctrl.onTranscriptionFailed = recorder.logVoiceTranscriptionFailed;
      await tester.pumpWidget(host(onText: (_) {}, controller: ctrl));
      await tester.pump();
      await tapMic(tester);
      await tapMic(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final ev = sessionAnalytics.bufferedEvents
          .where((e) => e['name'] == 'voice_transcription_failed')
          .single;
      final params = ev['params'] as Map;
      expect(params['sessionId'], recorder.sessionId);
      expect(params['agentId'], 'siu_yan');
      expect(params['category'], 'unavailable');
      expect(analytics.bufferedEvents, isEmpty,
          reason: 'logged once, through the session, not twice');
      recorder.dispose();
    });

    testWidgets('stopForSend while recording discards the clip (B03)',
        (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600)]);
      final client = FakeClient(const TranscriptionResult.ok('late text'));
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient = client;
      final ctrl = VoiceInputController();
      String? got;
      await tester.pumpWidget(host(onText: (t) => got = t, controller: ctrl));
      await tester.pump();
      await tapMic(tester);
      await ctrl.stopForSend();
      await tester.pump();
      expect(rec.cancels, 1);
      expect(client.received, isEmpty);
      expect(got, isNull);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      final (used, ms) = ctrl.takeModality();
      expect(used, isTrue);
      expect(ms, isNotNull);
    });

    testWidgets('no permission: hint, no recording, no S6, no event',
        (tester) async {
      final rec = FakeRecorder(permission: false);
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient =
          FakeClient(const TranscriptionResult.ok('x'));
      await tester.pumpWidget(host(onText: (_) {}));
      await tester.pump();
      await tapMic(tester);
      expect(rec.starts, 0);
      expect(find.text(VoiceCopy.s6TranscriptionFailed), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(analytics.bufferedEvents, isEmpty);
    });

    testWidgets('60 s cap stops the recording by itself', (tester) async {
      final rec = FakeRecorder(chunks: [_pcm(1600)]);
      final client = FakeClient(const TranscriptionResult.ok('長篇'));
      VoiceInputButton.debugRecorderFactory = () => rec;
      VoiceInputButton.debugTranscriptionClient = client;
      String? got;
      await tester.pumpWidget(host(onText: (t) => got = t));
      await tester.pump();
      await tapMic(tester);
      await tester.pump(VoiceInputButton.maxClip + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(rec.stops, 1);
      expect(got, '長篇');
    });
  });
}
