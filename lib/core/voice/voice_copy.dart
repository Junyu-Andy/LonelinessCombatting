/// Elder-visible voice-input copy (T27, SPEC:C18).
///
/// S6 is copied verbatim from `docs/spec/copy/short-texts.md` and checked
/// word for word by test/final_copy_test.dart.  It is shown next to the
/// input box after the server failed to transcribe (once retried), never as
/// a chat bubble and never written to turns or memory.  Both arms identical.
class VoiceCopy {
  VoiceCopy._();

  /// S6 — 语音转写失败（服务器重试 1 次后仍失败）.
  static const String s6TranscriptionFailed =
      '頭先段錄音轉唔到做文字，唔係你嘅問題。你可以打字話我知，或者等陣再試下講。';

  /// English UI only (testers / researchers; participants use Cantonese).
  /// Marked as a draft: no English S6 exists in the spec.
  static const String s6TranscriptionFailedEn =
      '【占位】The recording could not be turned into text. That is not your '
      'fault. You can type instead, or try speaking again in a moment.';
}
