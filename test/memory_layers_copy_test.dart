// T31 (decision 0035): S7 is copied word for word from the final copy, and
// its switch is off unless the config says literally true.
import 'dart:io';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/memory/data/memory_layers_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S7 matches docs/spec/copy/short-texts.md word for word', () {
    final row = File('docs/spec/copy/short-texts.md')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('| S7 |'));
    // | 编号 | 用在哪里 | 文字 | 说明 | 任务 |
    final text = row.split('|')[3].trim();
    expect(MemoryLayersCopy.s7, text);
  });

  test('the S7 notice switch is off unless literally true', () {
    expect(const RemoteFeatureFlags().memoryLayersNoticeEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({}).memoryLayersNoticeEnabled, isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'memoryLayersNoticeEnabled': 'true'})
            .memoryLayersNoticeEnabled,
        isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'memoryLayersNoticeEnabled': true})
            .memoryLayersNoticeEnabled,
        isTrue);
  });
}
