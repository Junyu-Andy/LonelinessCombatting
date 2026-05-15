/// Spec §M5 Arm B: fixed prompt set rotated on schedule. Multiple-choice
/// or short-text response.
///
/// 12 prompts is enough for 6 weeks of twice-weekly rotation without
/// repeats. Arm A doesn't read this list; its prompt is LLM-generated.
const reflectionPrompts = <(String zh, String en)>[
  (
    '今個禮拜，有冇一件你覺得自己處理得唔錯嘅事？',
    'Was there something this week you feel you handled OK?',
  ),
  (
    '邊一個人最近令你感到被了解？',
    'Who has made you feel understood lately?',
  ),
  (
    '今日最辛苦嘅時刻係幾點？嗰刻你做咗咩？',
    'What was the hardest moment today? What did you do in that moment?',
  ),
  (
    '最近有冇一個小決定，做完之後覺得自己鬆咗一啖氣？',
    'Was there a small decision recently that left you feeling a little lighter?',
  ),
  (
    '如果聽日你打算搵一個人傾偈，你最想搵邊個？',
    'If you were going to reach out to one person tomorrow, who would it be?',
  ),
  (
    '最近邊樣嘢令你笑過？',
    'What made you laugh recently?',
  ),
  (
    '今日你有冇照顧過自己嘅身體？例如食、瞓、行下。',
    'Did you take care of your body today — eating, sleeping, moving?',
  ),
  (
    '對你嚟講，今個禮拜咩係「足夠好」？',
    'What counted as "good enough" for you this week?',
  ),
  (
    '有冇邊個人嘅一句說話，最近仲喺你個心入面？',
    'Is there something someone said that\'s stayed with you lately?',
  ),
  (
    '你最近遇到嘅一個小阻滯，係咩？你係點面對佢？',
    'A small obstacle you ran into recently — what was it, and how did you meet it?',
  ),
  (
    '今日你期待嘅嘢係咩？',
    'What did you look forward to today?',
  ),
  (
    '如果可以同 30 年前嘅自己講一句說話，你會講咩？',
    'If you could say one sentence to yourself 30 years ago, what would it be?',
  ),
];
