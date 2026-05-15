// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '陪伴型 App Demo';

  @override
  String get homeTab => '首頁';

  @override
  String get contextTab => '了解你';

  @override
  String get actionTab => '做點活動';

  @override
  String get followUpTab => '跟進';

  @override
  String get settingsTab => '設定';

  @override
  String get homeSubtitle => '呢度係 demo 嘅首頁總覽。';

  @override
  String get homeStructureHint => '四個核心模組：建立信任 → 理解情境 → 行動支援 → 持續跟進。';

  @override
  String get contextSubtitle => '你嘅資料、最近狀態、跟進節奏。';

  @override
  String get actionSubtitle => '揀件令自己舒服啲嘅事，做返一啲就得。';

  @override
  String get followUpSubtitle => '提醒、進度同節奏。';

  @override
  String get settingsSubtitle => '語言、界線、demo 資料。';

  @override
  String get developerCredit => '由香港大學數據及系統工程學系開發';

  @override
  String get developerCreditShort => 'HKU DSE';

  @override
  String get onboardingWelcomeTitle => '慢慢開始';

  @override
  String get onboardingWelcomeBody => '睇一睇個 app 嘅結構。';

  @override
  String get onboardingHelpTitle => '可以點幫你';

  @override
  String get onboardingHelpBody => 'Check-in　•　整理社交　•　行動建議　•　跟進。';

  @override
  String get onboardingBoundaryTitle => '系統界線';

  @override
  String get onboardingBoundaryBody => '我哋只提供結構同建議。';

  @override
  String get onboardingBoundaryItemOne => '整理想法';

  @override
  String get onboardingBoundaryItemTwo => '細小行動建議';

  @override
  String get onboardingBoundaryItemThree => '❌ 唔係危機支援工具';

  @override
  String get onboardingStartTitle => '入去睇 demo';

  @override
  String get onboardingStartBody => '慢慢探索就得。';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get enterDemo => '進入 Demo';

  @override
  String get tabToday => '今日';

  @override
  String get tabMyStory => '人生點滴';

  @override
  String get tabMe => '我的記錄';

  @override
  String get greetingMorning => '早晨';
  @override
  String get greetingNoon => '午安';
  @override
  String get greetingAfternoon => '下午好';
  @override
  String get greetingEvening => '夜晚好';
  @override
  String get greetingNight => '夜深喇，慢慢嚟';

  @override
  String get todayCheckInTitle => '今日 Check-in';
  @override
  String get todayCheckInSubtitle => '用一分鐘紀錄一下今日嘅狀態。';
  @override
  String get todayMicroReflection => '一個反思';
  @override
  String get todayMicroInvitation => '今日嘅小邀請';
  @override
  String get todayActivePlanLabel => '今日嘅小行動';
  @override
  String get todayActivePlanEmpty => '今日未有計劃。';

  @override
  String myStoryWeekProgress(int current, int total) =>
      '第 $current 週 / 共 $total 週';
  @override
  String myStoryWeekTitle(int n) => '第 $n 週';
  @override
  String get myStorySessionNotStarted => '本週 session 未開始';
  @override
  String get myStorySessionInProgress => '上次傾到中途';
  @override
  String get myStorySessionCompleted => '本週已完成';
  @override
  String get myStoryStartCta => '開始';
  @override
  String get myStoryContinueCta => '繼續';
  @override
  String get myStoryRereadCta => '重讀';
  @override
  String get myStoryTimelineHeader => '你嘅故事線';
  @override
  String get myStoryHistoryHeader => '過往 sessions';
  @override
  String get myStoryHistoryEmpty => '暫時未有完成嘅 session。';

  @override
  String get meItemProgress => '你嘅一個禮拜';
  @override
  String get meItemActionLoop => '跟進計劃';
  @override
  String get meItemArticles => '讀少少';
  @override
  String get meItemCrisis => '危機支援';
  @override
  String get meItemProfile => '個人資料';
  @override
  String get meItemProgressSubtitle => '回顧每週嘅心情同社交';
  @override
  String get meItemActionLoopSubtitle => '睇下之前嘅小行動點樣';
  @override
  String get meItemArticlesSubtitle => '關於孤獨同身心嘅短文';
  @override
  String get meItemCrisisSubtitle => '緊急時搵到嘅人';
  @override
  String get meItemProfileSubtitle => '更新你嘅資料';

  @override
  String get safetyPillLow => '搵人傾';
  @override
  String get safetyPillModerate => '需要支援？';
  @override
  String get safetyPillAcute => '緊急熱線';
}

/// The translations for Chinese, as used in Hong Kong, using the Han script (`zh_Hant_HK`).
class AppLocalizationsZhHantHk extends AppLocalizationsZh {
  AppLocalizationsZhHantHk() : super('zh_Hant_HK');

  @override
  String get appTitle => '陪伴型 App Demo';

  @override
  String get homeTab => '首頁';

  @override
  String get contextTab => '了解你';

  @override
  String get actionTab => '行動支援';

  @override
  String get followUpTab => '跟進';

  @override
  String get settingsTab => '設定';

  @override
  String get homeSubtitle => '呢度係 demo 嘅首頁總覽。';

  @override
  String get homeStructureHint =>
      '呢個 demo 會用四個核心模組展示產品結構：建立信任、理解情境、行動支援，同持續跟進。';

  @override
  String get contextSubtitle => '呢度會放快速 check-in、social map 同最近互動反思。';

  @override
  String get actionSubtitle => '呢度會放個人化建議、開場白同活動建議。';

  @override
  String get followUpSubtitle => '呢度會放提醒、進度回顧同節奏調整。';

  @override
  String get settingsSubtitle => '呢度會放語言、系統界線同 demo 資訊。';

  @override
  String get onboardingWelcomeTitle => '用一個冇咁有壓力嘅方式開始';

  @override
  String get onboardingWelcomeBody => '呢個 demo 會展示個 app 嘅整體結構，同各個核心模組點樣串連起上嚟。';

  @override
  String get onboardingHelpTitle => '呢個 app 可以點幫你';

  @override
  String get onboardingHelpBody =>
      '佢可以引導你做 check-in、整理社交情境、提供細小可行嘅下一步，亦可以支援持續跟進。';

  @override
  String get onboardingBoundaryTitle => '系統界線';

  @override
  String get onboardingBoundaryBody => '呢個 demo 主要提供結構同建議，唔可以取代緊急支援、診斷或者專業照護。';

  @override
  String get onboardingBoundaryItemOne => '佢可以幫你整理想法，同預備下一步。';

  @override
  String get onboardingBoundaryItemTwo => '佢可以提供細小而具體嘅行動建議。';

  @override
  String get onboardingBoundaryItemThree => '佢唔應該被當成危機支援工具。';

  @override
  String get onboardingStartTitle => '準備入去睇 demo';

  @override
  String get onboardingStartBody => '你可以先由主結構開始睇，之後再逐步補齊每個模組嘅細節內容。';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get enterDemo => '進入 Demo';
}
