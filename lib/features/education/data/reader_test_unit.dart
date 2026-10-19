/// 1020c §4(1) — the placeholder test unit (content says 測試).
///
/// NOT part of the formal build: it is referenced only behind
/// `kReaderTestUnit` (`--dart-define=READER_TEST_UNIT=true`), a
/// compile-time constant, so a normal build tree-shakes these constants
/// out.  It is deliberately NOT under assets/readers/ (assets are always
/// packaged).  It also carries one external link and one external image
/// on purpose, to check on a phone that neither opens nor loads — so it
/// would fail tool/check_reader_html.js, which is correct for a real unit.
library;

import 'reader_unit.dart';

const ReaderUnit readerTestUnit = ReaderUnit(
  id: 'zz_test_unit',
  titleZh: '測試小讀本（測試用）',
  minutes: 3,
  order: 0,
);

const String readerTestUnitHtml = '''
<!doctype html>
<html lang="zh-HK">
<head>
<meta charset="utf-8">
<title>測試小讀本</title>
<style>
body{margin:0;padding:16px 18px 48px;font-family:sans-serif;color:#2b2b2b;
  background:#fffaf3;line-height:1.6;font-size:calc(19px * var(--fs, 1));}
h1{font-size:calc(26px * var(--fs, 1));margin:0 0 8px;}
h2{font-size:calc(22px * var(--fs, 1));margin:28px 0 8px;}
section{min-height:70vh;}
.note{background:#f1e6d6;border-radius:12px;padding:12px 14px;}
a.cta{display:block;margin:14px 0;padding:14px 16px;border-radius:14px;
  background:#7a4e2d;color:#fff;text-decoration:none;text-align:center;
  font-size:calc(20px * var(--fs, 1));}
a.ext{color:#7a4e2d;}
</style>
</head>
<body>
<h1>測試小讀本</h1>
<p class="note">呢篇只係測試用，唔係正式內容。</p>
<section data-section="s1_intro">
<h2>第一節：測試開頭</h2>
<p>測試文字。慢慢向下碌，睇下每一節會唔會記低。</p>
<p>測試：字號跟 App 設定（標準、特大都要試）。</p>
</section>
<section data-section="s2_middle">
<h2>第二節：測試中間</h2>
<p>測試：下面呢條係外面嘅連結，撳咗應該乜都唔發生，唔會開瀏覽器。</p>
<p><a class="ext" href="https://www.example.com/">外面嘅連結（測試）</a></p>
<p>測試：下面呢張圖來自網上，應該唔會顯示（App 唔准連外網）。</p>
<p><img src="https://www.example.com/test.png" alt="（測試：外部圖片，唔應該顯示）" width="120" height="60"></p>
</section>
<section data-section="s3_actions">
<h2>第三節：測試三個按鈕</h2>
<a class="cta" href="peizhu://cta/small_action">今日嘅小邀請（測試）</a>
<a class="cta" href="peizhu://cta/plan">我嘅計劃，新建（測試）</a>
<a class="cta" href="peizhu://cta/thought">望一望心入面（測試）</a>
<p>測試完。撳返回應該返去「讀少少」。</p>
</section>
</body>
</html>
''';

const String readerTestUnitText = '''
測試小讀本

呢篇只係測試用，唔係正式內容。

第一節：測試開頭
測試文字。慢慢向下碌，睇下每一節會唔會記低。
測試：字號跟 App 設定（標準、特大都要試）。

第二節：測試中間
測試：外面嘅連結撳咗應該乜都唔發生，唔會開瀏覽器；網上嘅圖唔會顯示。

第三節：測試三個按鈕
今日嘅小邀請、我嘅計劃、望一望心入面。
''';
