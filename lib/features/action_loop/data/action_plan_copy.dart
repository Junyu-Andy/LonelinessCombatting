/// 1020e 二.7 — elder-facing text for the simplified action plan and the
/// edit / delete page (switch actionPlanSimplifiedEnabled).
///
/// 【草稿】Every line here is a DRAFT.  Junyu decides the wording from the
/// PR screenshots (docs/dev-reports/action-plan-v2-shots/); change it here
/// only.  Both arms show exactly the same text.
class ActionPlanCopy {
  const ActionPlanCopy._();

  /// Suffix on the optional items (邊度 / 同邊個 / 如果唔成功).
  static const optionalSuffix = '（可以唔揀）';

  /// Hybrid steps that may be skipped: label suffix.
  static const optionalTypedSuffix = '（可以唔填）';

  /// Rule arm: shown above 儲存計劃 while it cannot be saved yet.
  static const saveHint = '寫低「做咩」、揀「幾時」，就可以儲存。';

  /// Hybrid: 下一步 pressed on an empty required step.
  static const emptyStepHint = '寫少少就得，例如「聽朝」。';

  /// Hybrid: card on top of each step once 做咩 is known.
  static String youWantTo(String action) => '你想做：$action';

  /// Hybrid review: optional extra steps.
  static const addDetails = '加多啲細節（可以唔填）';

  /// Hybrid optional steps: skip button.
  static const skip = '跳過';

  /// 等住跟進 card buttons.
  static const edit = '改';
  static const delete = '刪除';

  /// Edit page.
  static const editTitle = '改計劃';
  static const editWhat = '做咩';
  static const editWhen = '幾時';
  static const editSave = '儲存';
  static const editDelete = '刪除呢個計劃';
  static const editNeedBoth = '「做咩」同「幾時」都要寫。';

  /// Delete confirm dialog.
  static const deleteConfirm = '刪咗呢個計劃？';
  static const deleteYes = '刪除';
  static const deleteNo = '唔刪';

  /// After deleting.
  static const deleted = '已經刪咗。';
}
