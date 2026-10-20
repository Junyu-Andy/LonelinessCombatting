/// 1020c §1(6) — 「問下通通」 on a 小讀本 (Hybrid arm only, registry C08).
///
/// The Q&A is the existing article Q&A: 通通's chat page in article mode
/// (TungTungPage with `articleContext`), whose persona prompt is the
/// server's `tung_tung.v3` and already says 「你叫通通（一個電腦程式夥伴）」.
/// The only App-side words are the header in front of the article text.
/// For a 小讀本 the App sends this reader-specific header instead of the
/// article one; the 15 articles keep theirs unchanged.  Its first line is
/// the article-mode marker the persona prompt already knows; the second
/// line uses the 「電腦程式夥伴」 wording of the v2 companion prompts (#118,
/// as in social_suggestions_page `_systemPromptZhV2`).
///
/// DRAFT — wording for Junyu to confirm (1020c 共同规则 (4)).
library;

const String kReaderQaHeaderZh = '[文章內容 — 所有回答只可以根據呢段]\n'
    '（呢段係「讀少少」入面嘅小讀本。你係通通（一個電腦程式夥伴），'
    '幫佢明白佢啱啱讀緊嘅內容；小讀本冇講嘅，就老實講'
    '「呢個我都唔係好肯定，小讀本入面冇講」。'
    '唔好用「AI」「模型」「機械人」呢啲字。）';

const String kReaderQaHeaderEn =
    '[Article context — ground all answers in this text]\n'
    '(This is a short reader from "Read a little". You are Tung Tung, a '
    'computer-program companion; help them understand what they just '
    'read. If the reader does not cover it, say honestly that you are not '
    'sure. Do not use the words "AI", "model" or "robot".)';

/// `tungTung.articleId` for a 小讀本 (keeps them apart from the 15
/// articles' ids in the turn logs).
String readerQaArticleId(String unitId) => 'reader_$unitId';
