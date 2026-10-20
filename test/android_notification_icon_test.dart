// 10/20 (decisions-log 99/100) — every Android notification uses the white
// 陪住 silhouette on the theme colour.  File checks only (no Android build
// here): the manifest points FCM at the icon and colour, the icon exists at
// all five densities, and it is white on transparent (Android uses only its
// alpha channel).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

void main() {
  test('manifest: FCM default notification icon and colour', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        manifest,
        contains('android:name="com.google.firebase.messaging.'
            'default_notification_icon"'));
    expect(manifest, contains('android:resource="@drawable/ic_stat_peizhu"'));
    expect(
        manifest,
        contains('android:name="com.google.firebase.messaging.'
            'default_notification_color"'));
    expect(manifest,
        contains('android:resource="@color/notification_color"'));
    expect(File('$_res/values/colors.xml').readAsStringSync(),
        contains('<color name="notification_color">#C2703F</color>'));
  });

  testWidgets('icon at five densities, 24 dp, white on transparent',
      (tester) async {
    const sizes = {
      'mdpi': 24,
      'hdpi': 36,
      'xhdpi': 48,
      'xxhdpi': 72,
      'xxxhdpi': 96,
    };
    for (final MapEntry(key: density, value: px) in sizes.entries) {
      final file = File('$_res/drawable-$density/ic_stat_peizhu.png');
      expect(file.existsSync(), isTrue, reason: density);
      final rgba = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, px, reason: density);
        expect(frame.image.height, px, reason: density);
        final data = await frame.image
            .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        return data!.buffer.asUint8List();
      });
      var opaque = 0, transparent = 0;
      for (var i = 0; i < rgba!.length; i += 4) {
        if (rgba[i + 3] > 0) {
          opaque++;
          expect([rgba[i], rgba[i + 1], rgba[i + 2]], [255, 255, 255],
              reason: density);
        } else {
          transparent++;
        }
      }
      expect(opaque, greaterThan(0), reason: density);
      expect(transparent, greaterThan(0), reason: density);
    }
  });
}
