/// T31 (decision 0034) — S7, the memory-layers notice at the top of the
/// 「我記得嘅嘢」 page.  Copied word for word from
/// `docs/spec/copy/short-texts.md` (S7); test/memory_layers_copy_test.dart
/// checks it against that file.  Shown only while
/// `RemoteFeatureFlags.memoryLayersNoticeEnabled` is on.
library;

class MemoryLayersCopy {
  const MemoryLayersCopy._();

  static const String s7 =
      '三位都會記得一啲基本嘢，例如你鍾意人點叫你、屋企人同朋友係邊個、'
      '你同邊個一齊住、平時點樣過日子、你鍾意做啲乜。'
      '你同其中一位講過嘅心事、身體情況、舊時嘅故事，'
      '同埋佢答應咗下次再問你嘅嘢，就只有嗰一位記得，其他兩位唔會知。'
      '你可以叫佢今次唔好記住，亦都可以喺設定度刪除任何一樣記住咗嘅嘢。';
}
