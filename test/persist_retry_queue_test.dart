import 'dart:async';

import 'package:app_demo/core/connectivity/persist_retry_queue.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersistRetryQueue', () {
    test('flush replays a queued op and drops it on success', () async {
      final events = <String>[];
      final q = PersistRetryQueue(
        retryInterval: null,
        telemetry: (e, _) => events.add(e),
      );
      var ran = 0;
      q.enqueue('t', () async => ran++);
      expect(q.pendingCount, 1);
      await q.flush();
      expect(ran, 1);
      expect(q.pendingCount, 0);
      expect(events, ['persist_retry_enqueued', 'persist_retry_succeeded']);
      q.dispose();
    });

    test('a persistently failing op is dropped after maxAttempts', () async {
      final events = <String>[];
      final q = PersistRetryQueue(
        retryInterval: null,
        maxAttempts: 3,
        telemetry: (e, _) => events.add(e),
      );
      var attempts = 0;
      q.enqueue('t', () async {
        attempts++;
        throw StateError('still down');
      });
      for (var i = 0; i < 5; i++) {
        await q.flush();
      }
      expect(attempts, 3);
      expect(q.pendingCount, 0);
      expect(events.last, 'persist_retry_dropped');
      q.dispose();
    });

    test('connectivity-restored event triggers a flush', () async {
      final online = StreamController<bool>();
      var ran = 0;
      final q = PersistRetryQueue(
        retryInterval: null,
        onStatusChange: online.stream,
      );
      q.enqueue('t', () async => ran++);
      online.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(ran, 1);
      expect(q.pendingCount, 0);
      q.dispose();
      await online.close();
    });
  });

  group('persistQuietly retry policy', () {
    final events = <(String, Map<String, dynamic>)>[];
    late PersistRetryQueue queue;

    setUp(() {
      events.clear();
      queue = PersistRetryQueue(retryInterval: null);
      persistRetryQueue = queue;
      persistTelemetry = (e, p) => events.add((e, p));
    });

    tearDown(() {
      queue.dispose();
      persistRetryQueue = null;
      persistTelemetry = null;
    });

    test('unavailable → persist_failed telemetry + enqueued for replay',
        () async {
      await persistQuietly(
        'tag',
        () async =>
            throw FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );
      expect(events.single.$1, 'persist_failed');
      expect(events.single.$2['code'], 'FS-02');
      expect(queue.pendingCount, 1);
    });

    test('permission-denied → telemetry as FS-01, NOT enqueued', () async {
      await persistQuietly(
        'tag',
        () async => throw FirebaseException(
            plugin: 'firestore', code: 'permission-denied'),
      );
      expect(events.single.$2['code'], 'FS-01');
      expect(queue.pendingCount, 0);
    });

    test('guard timeout → telemetry only (SDK still owns the write)',
        () async {
      await persistQuietly(
        'tag',
        () async => throw TimeoutException('hang'),
      );
      expect(events.single.$2['code'], 'FS-02');
      expect(events.single.$2['detail'], 'guard timeout');
      expect(queue.pendingCount, 0);
    });

    test('unexpected error → telemetry as UNK-01 + enqueued', () async {
      await persistQuietly('tag', () async => throw StateError('boom'));
      expect(events.single.$2['code'], 'UNK-01');
      expect(queue.pendingCount, 1);
    });
  });
}
