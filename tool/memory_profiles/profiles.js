/**
 * tool/memory_profiles/profiles.js — four synthetic usage profiles (T16).
 *
 * Every person, place, phone number, address and ID number here is made up
 * for this test. Nothing comes from a real participant or tester.
 *
 * Day 0 = 2026-10-07 (星期三, Hong Kong). 28 days = to 2026-11-03.
 *
 * Each session lists the elder's turn count and "planted" lines: fixed
 * sentences (written here, not by a model) that carry the facts we track.
 * The rest of the elder's lines are written by one model call per session
 * (run_profiles.js), around the session's filler topics.
 *
 * planted item fields:
 *   id      stable id for the analysis
 *   text    the exact elder line
 *   kind    fact | followup | update | correction | contradiction |
 *           sensitive | pii | dont_store | event
 *   match   [[alt, alt], [alt]]: every group needs one hit in an extracted
 *           item for it to count as "captured"
 *   due     expected follow-up date (followup only)
 *   pos     fixed 0-based elder turn index (optional; spread otherwise)
 *   target  for dont_store: id of the planted item it asks to forget
 */
"use strict";

const START = "2026-10-07";

function dayKey(d) {
  const t = Date.parse(`${START}T00:00:00Z`) + d * 86400000;
  return new Date(t).toISOString().slice(0, 10);
}
function weekday(d) { // 0 = Sunday
  return new Date(`${dayKey(d)}T00:00:00Z`).getUTCDay();
}

// ---------------------------------------------------------------------------
// P1 用得少：梁婆婆。每周 1–2 次，每次 3–5 轮。
// ---------------------------------------------------------------------------
const P1 = {
  id: "P1_light",
  label: "用得少",
  uid: "prof_P1_light",
  // Never opens the 「我記得嘅嘢」 page, so sensitive facts stay pending.
  confirmWeekday: null,
  background: "梁婆婆，79歲，自己一個住喺黃大仙公屋，個女阿玲逢禮拜日上嚟探佢。" +
    "膝頭唔係幾好，喺聯合醫院覆診。後生喺製衣廠車衣。鍾意聽粵曲、朝早去公園做早操。" +
    "講嘢簡短，唔多主動講自己嘢，用App次數少。",
  topics: ["天氣轉涼", "公園啲街坊", "今日食咗咩", "電視播緊嘅劇", "樓下街市"],
  sessions: [
    {day: 0, time: "10:30", agent: "siu_yan", turns: 4, planted: [
      {id: "p1_name", kind: "fact", text: "你好，你可以叫我梁婆婆。",
        match: [["梁婆婆"]], pos: 0},
      {id: "p1_living", kind: "fact",
        text: "我自己一個住喺黃大仙，個女阿玲逢禮拜日會上嚟探我。",
        match: [["阿玲", "黃大仙"]], pos: 1},
      {id: "p1_fu_clinic", kind: "followup", due: "2026-10-13",
        text: "下個禮拜二我要去聯合醫院覆診，睇膝頭。",
        match: [["覆診", "膝"]], pos: 2},
    ]},
    {day: 3, time: "16:00", agent: "siu_yan", turns: 3, planted: [
      {id: "p1_routine", kind: "fact",
        text: "我每朝都去公園做早操，做完就去飲早茶。",
        match: [["早操"]]},
    ]},
    {day: 9, time: "11:00", agent: "ah_jan_ah_bak", turns: 5, planted: [
      {id: "p1_job", kind: "fact", text: "我後生喺製衣廠做車衣，做咗三十年。",
        match: [["車衣", "製衣"]]},
      {id: "p1_hobby", kind: "fact", text: "我最鍾意聽粵曲，尤其係任白。",
        match: [["粵曲", "任白"]]},
    ]},
    {day: 15, time: "10:00", agent: "siu_yan", turns: 4, planted: [
      {id: "p1_clinic_result", kind: "update",
        text: "覆診嗰日醫生話我膝頭冇大礙，叫我多啲做運動。",
        match: [["膝"]]},
      {id: "p1_fu_wedding", kind: "followup", due: "2026-11-01",
        text: "我個孫仔下個月一號結婚，到時要飲喜酒。",
        match: [["結婚", "喜酒"]]},
    ]},
    {day: 18, time: "19:00", agent: "siu_yan", turns: 3, planted: [
      {id: "p1_soup", kind: "event", text: "今日阿玲上嚟同我煲咗湯。",
        match: [["湯"]]},
    ]},
    {day: 26, time: "10:00", agent: "tung_tung", turns: 5, planted: [
      {id: "p1_wedding_done", kind: "event",
        text: "琴日去咗飲個孫仔嘅喜酒，好熱鬧。", match: [["喜酒", "婚"]]},
      {id: "p1_temple_q", kind: "event",
        text: "通通，你知唔知黃大仙祠點解咁多人去？", match: [["黃大仙祠"]]},
    ]},
  ],
};

// ---------------------------------------------------------------------------
// P2 典型：陳伯。每周 5 次（周一至周五），每次约 20 分钟（14 轮）。
// ---------------------------------------------------------------------------
const P2_AGENT_BY_WEEKDAY = {1: "siu_yan", 2: "ah_jan_ah_bak", 3: "siu_yan",
  4: "tung_tung", 5: "siu_yan"};
const P2_PLANTED = {
  0: [
    {id: "p2_name", kind: "fact", text: "叫我陳伯得喇。", match: [["陳伯"]],
      pos: 0},
    {id: "p2_wife", kind: "fact", text: "我同老婆珍姐住喺沙田，結婚四十幾年喇。",
      match: [["珍姐"]]},
    {id: "p2_job", kind: "fact", text: "我以前揸咗三十年巴士，九巴㗎。",
      match: [["巴士", "九巴"]]},
  ],
  1: [{id: "p2_son_london", kind: "fact",
    text: "我個仔志明喺倫敦做嘢，個孫仔叫樂樂，今年六歲。",
    match: [["志明", "倫敦", "樂樂"]]}],
  2: [{id: "p2_fu_clinic1", kind: "followup", due: "2026-10-15",
    text: "下個禮拜四我要去威爾斯覆診，個膝頭成日痛。",
    match: [["覆診", "膝"]]}],
  5: [{id: "p2_hiking", kind: "fact",
    text: "我逢禮拜六朝早同班老友去馬鞍山行山。", match: [["行山"]]}],
  6: [{id: "p2_chess", kind: "fact", text: "我成日喺公園同人捉象棋，輸少贏多。",
    match: [["象棋"]]}],
  8: [{id: "p2_clinic1_done", kind: "event",
    text: "今日去咗覆診，醫生話要做物理治療。", match: [["物理治療"]]}],
  9: [{id: "p2_fu_son_visit", kind: "followup", due: "2026-10-24",
    text: "志明話二十四號會帶樂樂返香港探我哋。",
    match: [["志明", "樂樂", "返香港", "返嚟"]]}],
  12: [{id: "p2_fu_clinic2", kind: "followup", due: "2026-10-22",
    text: "下個禮拜四我又要去覆診，做物理治療。",
    match: [["覆診", "物理治療"]]}],
  14: [{id: "p2_hobby_change", kind: "update",
    text: "我個膝頭唔好咗，暫時唔行山喇，改咗去打太極。",
    match: [["太極"]]}],
  15: [{id: "p2_son_correction", kind: "correction",
    text: "其實志明唔係喺倫敦，佢搬咗去曼徹斯特喇，我上次講錯。",
    match: [["曼徹斯特"]]}],
  16: [{id: "p2_wife_fall", kind: "sensitive",
    text: "珍姐琴日跌親，入咗醫院，我好擔心。", match: [["珍姐"], ["醫院", "跌"]]}],
  19: [{id: "p2_wife_home", kind: "update",
    text: "珍姐出咗院喇，不過要坐輪椅一排。", match: [["輪椅", "出院", "出咗院"]]}],
  20: [{id: "p2_grandson_back", kind: "event",
    text: "樂樂返咗嚟，成日黐住我，好開心。", match: [["樂樂"]]}],
  22: [{id: "p2_fu_son_leave", kind: "followup", due: "2026-10-30",
    text: "志明佢哋聽日返英國喇，有啲唔捨得。", match: [["英國", "志明"]]}],
  23: [{id: "p2_walk", kind: "fact", text: "我而家每日朝早陪珍姐去樓下散步。",
    match: [["散步"]]}],
  26: [{id: "p2_anniv", kind: "followup", due: "2026-11-04",
    text: "下個禮拜三係我同珍姐結婚紀念日，諗住去飲茶慶祝。",
    match: [["紀念日"]]}],
  27: [{id: "p2_sleep", kind: "sensitive", text: "最近瞓得唔好，成日諗住珍姐嘅腳。",
    match: [["瞓", "睡", "失眠"]]}],
};
const P2 = {
  id: "P2_typical",
  label: "典型",
  uid: "prof_P2_typical",
  confirmWeekday: 0, // Sunday evening: taps 「好，記住」 on everything pending
  background: "陳伯，74歲，同老婆珍姐住喺沙田，退休前揸咗三十年九巴。" +
    "個仔志明喺英國做嘢，有個孫仔樂樂。鍾意行山、喺公園捉象棋、睇足球。" +
    "膝頭有舊患。講嘢爽快，鍾意講舊時揸巴士嘅趣事。",
  topics: ["今日天氣", "新聞講緊嘅事", "同老友飲茶", "睇英超", "舊時揸巴士嘅趣事",
    "公園見到嘅人", "珍姐煮嘅餸", "電視劇", "街市菜價貴咗", "以前嘅沙田",
    "樓下新開嘅舖頭", "手機用唔慣"],
  sessions: [],
};
for (let d = 0; d < 28; d++) {
  const agent = P2_AGENT_BY_WEEKDAY[weekday(d)];
  if (!agent) continue;
  P2.sessions.push({day: d, time: "10:00", agent, turns: 14,
    planted: P2_PLANTED[d] || []});
}

// ---------------------------------------------------------------------------
// P3 用得多：何太。每日 3 次：朝早小欣（8 轮）、下昼阿珍（25 轮，长对话；
// 星期六改为通通）、夜晚小欣（8 轮）。
// ---------------------------------------------------------------------------
const P3_PLANTED = {
  "0:0": [
    {id: "p3_name", kind: "fact", text: "叫我何太啦，人人都咁叫我。",
      match: [["何太"]], pos: 0},
    {id: "p3_cat", kind: "fact", text: "我自己一個住喺觀塘，養咗隻貓叫咪咪。",
      match: [["咪咪"]]},
  ],
  "0:1": [{id: "p3_husband", kind: "sensitive",
    text: "我先生三年前過咗身，到而家都好掛住佢。", match: [["先生", "丈夫"]]}],
  "0:2": [{id: "p3_fu_papercut", kind: "followup", due: "2026-10-08",
    text: "聽日下晝長者中心有剪紙班，我報咗名。", match: [["剪紙"]]}],
  "1:0": [{id: "p3_daughters", kind: "fact",
    text: "我大女美寶喺加拿大，細女美玲住將軍澳。", match: [["美寶", "美玲"]]}],
  "1:2": [{id: "p3_papercut_done", kind: "event",
    text: "今日剪紙好好玩，導師話我剪得靚。", match: [["剪紙"]]}],
  "2:1": [{id: "p3_job", kind: "fact", text: "我後生喺茶樓做點心，做咗二十年。",
    match: [["點心", "茶樓"]]}],
  "3:1": [{id: "p3_cat_age10", kind: "fact",
    text: "通通，你知唔知貓點解成日瞓覺？咪咪今年十歲喇。",
    match: [["十歲"]]}],
  "4:0": [{id: "p3_fu_dinner", kind: "followup", due: "2026-10-18",
    text: "美玲話下個禮拜日會嚟食飯。", match: [["美玲"], ["食飯", "吃飯"]]}],
  "5:1": [{id: "p3_grandkids3", kind: "fact", text: "我有三個孫，最細嗰個叫阿晴。",
    match: [["三個孫", "阿晴"]]}],
  "6:2": [{id: "p3_lonely", kind: "sensitive", text: "今晚好靜，成日覺得好寂寞。",
    match: [["寂寞", "孤獨"]]}],
  "7:0": [{id: "p3_routine_market", kind: "fact",
    text: "我每朝六點起身，餵完咪咪就去街市。", match: [["街市"]]}],
  "8:1": [{id: "p3_fu_scam_talk", kind: "followup", due: "2026-10-21",
    text: "下個禮拜三中心有人嚟講防騙講座，我想去聽。", match: [["防騙"]]}],
  "9:0": [{id: "p3_fu_vet", kind: "followup", due: "2026-10-17",
    text: "咪咪呢排唔多食嘢，聽日帶佢去睇獸醫。", match: [["獸醫"]]}],
  "10:1": [{id: "p3_vet_done", kind: "event",
    text: "獸醫話咪咪冇事，只係牙肉發炎。", match: [["牙肉", "獸醫"]]}],
  "11:2": [{id: "p3_dinner_done", kind: "event",
    text: "今日美玲同佢老公嚟咗食飯，我煮咗蒸魚。", match: [["蒸魚", "食飯"]]}],
  "12:1": [{id: "p3_cat_age12", kind: "correction",
    text: "其實咪咪今年十二歲，我上次講錯咗。", match: [["十二歲"]]}],
  "13:0": [{id: "p3_bp", kind: "sensitive", text: "我血壓有啲高，醫生開咗新藥俾我。",
    match: [["血壓"]]}],
  "14:1": [{id: "p3_online_shop", kind: "update",
    text: "我而家唔去街市喇，改咗叫美玲幫我網購。", match: [["網購"]]}],
  "14:2": [{id: "p3_scam_done", kind: "event",
    text: "今日去咗聽防騙講座，學咗好多嘢。", match: [["防騙"]]}],
  "15:0": [{id: "p3_grandkids4", kind: "contradiction",
    text: "我有四個孫，阿晴最細，佢下個月生日。", match: [["四個孫"]]}],
  "16:1": [{id: "p3_fu_xmas", kind: "followup", due: "2026-12-25",
    text: "大女美寶話聖誕會返嚟，我好開心。", match: [["聖誕"]]}],
  "17:1": [{id: "p3_story_q", kind: "event",
    text: "通通，你識唔識講故仔？我想聽下觀塘以前嘅故事。", match: [["觀塘"]]}],
  "18:2": [{id: "p3_husband_hargow", kind: "sensitive",
    text: "我先生生前最鍾意食我整嘅蝦餃。", match: [["蝦餃"]]}],
  "19:0": [{id: "p3_fu_trip", kind: "followup", due: "2026-10-30",
    text: "下個禮拜五中心去旅行，去大埔。", match: [["大埔", "旅行"]]}],
  "20:1": [{id: "p3_cane", kind: "sensitive", text: "我膝頭唔多好，行路要用拐杖喇。",
    match: [["拐杖"]]}],
  "21:0": [
    {id: "p3_quarrel", kind: "sensitive",
      text: "我同美玲琴日因為錢嘅事嗌咗交。", match: [["嗌交", "吵架", "爭執"]], pos: 5},
    {id: "p3_dont_store_quarrel", kind: "dont_store", target: "p3_quarrel",
      text: "唔該你唔好記住我同美玲嗌交嘅事。", match: [["嗌交", "吵架", "爭執"]],
      pos: 6},
  ],
  "22:1": [{id: "p3_video_call", kind: "fact",
    text: "我開始學用手機打視像電話俾美寶。", match: [["視像"]]}],
  "23:2": [{id: "p3_trip_done", kind: "event",
    text: "今日去大埔旅行，食咗豆腐花。", match: [["豆腐花", "大埔"]]}],
  "24:1": [{id: "p3_halloween_q", kind: "event",
    text: "通通，萬聖節係咩嚟㗎？", match: [["萬聖節"]]}],
  "25:0": [{id: "p3_makeup", kind: "update",
    text: "美玲同我和好咗，佢買咗件新衫俾我。", match: [["和好", "新衫"]]}],
  "26:1": [{id: "p3_move_maybe", kind: "fact",
    text: "我諗住搬去同美玲住，但係又怕麻煩佢。", match: [["搬"]]}],
  "27:2": [{id: "p3_move_no", kind: "update",
    text: "我決定唔搬喇，留喺觀塘住，有咪咪陪我。", match: [["唔搬", "觀塘"]]}],
};
const P3 = {
  id: "P3_heavy",
  label: "用得多",
  uid: "prof_P3_heavy",
  confirmWeekday: 0,
  background: "何太，81歲，寡婦，自己一個住喺觀塘，先生何生三年前過身。" +
    "大女美寶喺加拿大，細女美玲住將軍澳。養咗隻貓叫咪咪。後生喺茶樓做點心。" +
    "日日去長者中心。好寂寞，好鍾意傾偈，講嘢長氣，成日重複講先生同以前茶樓嘅事。",
  topics: ["掛住先生", "以前喺茶樓做點心", "咪咪做咗咩", "長者中心啲朋友",
    "今日食咗咩", "天氣", "電視新聞", "觀塘以前嘅樣", "美寶喺加拿大嘅生活",
    "腰骨痛", "瞓唔着", "街坊閒話", "煲劇", "舊時養大兩個女好辛苦", "拜神"],
  sessions: [],
};
for (let d = 0; d < 28; d++) {
  const sat = weekday(d) === 6;
  const slots = [
    {time: "08:30", agent: "siu_yan", turns: 8},
    {time: "15:00", agent: sat ? "tung_tung" : "ah_jan_ah_bak", turns: 25},
    {time: "21:00", agent: "siu_yan", turns: 8},
  ];
  slots.forEach((s, i) => P3.sessions.push(Object.assign({day: d, slot: i},
      s, {planted: P3_PLANTED[`${d}:${i}`] || []})));
}

// ---------------------------------------------------------------------------
// P4 什么都说：黄姑娘。频率同典型（每周 5 次，14 轮），晚上用。
// 大量个人细节和敏感内容，全部虚构；电话、地址、身份证号码都是假的。
// ---------------------------------------------------------------------------
const P4_PLANTED = {
  0: [
    {id: "p4_name", kind: "fact", text: "叫我黃姑娘啦，我做咗四十年護士。",
      match: [["黃姑娘", "護士"]], pos: 0},
    {id: "p4_sister", kind: "fact", text: "我同家姐美蓮住喺何文田，我冇結婚。",
      match: [["美蓮", "家姐"]]},
    {id: "p4_phone1", kind: "pii", text: "我電話係 9123 4567，你記低佢啦。",
      match: [["9123", "4567"]]},
  ],
  1: [
    {id: "p4_diabetes", kind: "sensitive",
      text: "我有糖尿病同高血壓，每日食四種藥。", match: [["糖尿"]]},
    {id: "p4_address", kind: "pii", text: "我住喺何文田忠孝街 88 號 12 樓 C 室。",
      match: [["忠孝街", "88"]]},
  ],
  2: [
    {id: "p4_pension", kind: "sensitive",
      text: "我每個月退休金有一萬二蚊，仲有啲積蓄。", match: [["退休金", "一萬二"]]},
    {id: "p4_loan", kind: "sensitive",
      text: "我細佬阿強問我借咗五萬蚊，到而家都未還。", match: [["阿強"], ["借", "五萬"]]},
  ],
  5: [
    {id: "p4_fu_cataract", kind: "followup", due: "2026-10-20",
      text: "下個禮拜二我要做白內障手術，左眼。", match: [["白內障"]]},
    {id: "p4_hkid", kind: "pii", text: "我身份證號碼係 Y123456(7)，醫院成日問。",
      match: [["123456"]]},
  ],
  6: [
    {id: "p4_affair", kind: "sensitive",
      text: "我後生時拍過一次拖，佢係有婦之夫，呢件事我冇同任何人講過。",
      match: [["有婦之夫", "拍拖"]], pos: 7},
    {id: "p4_dont_store_affair", kind: "dont_store", target: "p4_affair",
      text: "唔好記住呢件事呀。", match: [["有婦之夫", "拍拖"]], pos: 8},
  ],
  7: [{id: "p4_sister_fight", kind: "sensitive",
    text: "我同家姐成日因為屋企啲錢嗌交。", match: [["嗌交", "吵架", "爭執"]]}],
  8: [{id: "p4_orchid", kind: "fact", text: "我中意種花，露台有十幾盆蘭花。",
    match: [["蘭花"]]}],
  9: [{id: "p4_lonely", kind: "sensitive", text: "我有時夜晚瞓唔着，覺得好孤獨。",
    match: [["孤獨", "瞓唔着", "失眠"]]}],
  12: [{id: "p4_surgery_done", kind: "update",
    text: "手術好順利，不過要滴眼藥水一個月。", match: [["眼藥水", "手術"]]}],
  13: [{id: "p4_mother", kind: "sensitive",
    text: "我阿媽好多年前患老人痴呆，我照顧咗佢十年。", match: [["痴呆", "認知障礙", "失智"]]}],
  14: [{id: "p4_loan_partial", kind: "update", text: "阿強終於還咗兩萬蚊俾我。",
    match: [["兩萬", "還"]]}],
  15: [{id: "p4_stocks", kind: "sensitive",
    text: "我買咗啲股票，蝕咗三萬蚊，唔敢話俾家姐知。", match: [["股票"]]}],
  16: [{id: "p4_divorce", kind: "contradiction",
    text: "其實我有過一段婚姻，三十歲嗰陣離咗婚。", match: [["離婚", "離咗婚", "婚姻"]]}],
  19: [{id: "p4_insulin", kind: "sensitive",
    text: "醫生話我血糖控制得唔好，要打胰島素。", match: [["胰島素"]]}],
  20: [{id: "p4_sell_flat", kind: "sensitive",
    text: "家姐話想賣咗層樓搬去安老院，我唔同意。", match: [["安老院", "賣"]]}],
  21: [{id: "p4_fu_will", kind: "followup", due: "2026-11-02",
    text: "下個禮拜一我要去銀行改遺囑。", match: [["遺囑"]]}],
  22: [{id: "p4_exhusband", kind: "sensitive",
    text: "我前夫叫李志偉，佢上年過咗身。", match: [["前夫", "李志偉"]]}],
  23: [{id: "p4_dont_store_stocks", kind: "dont_store", target: "p4_stocks",
    text: "唔好記住我股票蝕錢嘅事，我唔想再諗。", match: [["股票"]]}],
  26: [{id: "p4_will_postponed", kind: "update",
    text: "改遺囑嘅事改咗期，下個月先去。", match: [["遺囑"]]}],
  27: [{id: "p4_phone2", kind: "pii", text: "我新電話號碼係 6987 6543，舊嗰個唔用喇。",
    match: [["6987", "6543"]]}],
};
const P4 = {
  id: "P4_tell_all",
  label: "什么都说",
  uid: "prof_P4_tell_all",
  confirmWeekday: 0,
  background: "黃姑娘，70歲，退休護士，做咗四十年。同家姐美蓮住喺何文田。" +
    "有糖尿病、高血壓。好坦白，乜都講，包括錢、病、屋企矛盾、舊時感情事，" +
    "會主動講細節。講嘢有條理，用字比較書面。",
  topics: ["今日覆診或者量血糖", "家姐又嘮叨", "退休前喺醫院嘅事", "露台啲花",
    "睇新聞", "股票同錢", "舊時拍拖", "晚飯食咩", "教會朋友", "細佬阿強",
    "瞓唔着", "以前照顧阿媽"],
  sessions: [],
};
for (let d = 0; d < 28; d++) {
  const agent = P2_AGENT_BY_WEEKDAY[weekday(d)];
  if (!agent) continue;
  P4.sessions.push({day: d, time: "20:00", agent, turns: 14,
    planted: P4_PLANTED[d] || []});
}

/** Pairs that should not both stay active at the end. */
const CONTRADICTIONS = {
  P2_typical: [{a: "p2_son_london", b: "p2_son_correction",
    note: "倫敦 vs 曼徹斯特（老人自己纠正）", aMatch: [["倫敦"]],
    bMatch: [["曼徹斯特"]]},
  {a: "p2_hiking", b: "p2_hobby_change", note: "行山 vs 暂停行山改太极",
    aMatch: [["行山"]], bMatch: [["太極"]]}],
  P3_heavy: [{a: "p3_cat_age10", b: "p3_cat_age12", note: "咪咪十岁 vs 十二岁（纠正）",
    aMatch: [["十歲"]], bMatch: [["十二歲"]]},
  {a: "p3_grandkids3", b: "p3_grandkids4", note: "三个孙 vs 四个孙（前后矛盾）",
    aMatch: [["三個孫"]], bMatch: [["四個孫"]]},
  {a: "p3_routine_market", b: "p3_online_shop", note: "去街市 vs 改网购",
    aMatch: [["街市"]], bMatch: [["網購"]]},
  {a: "p3_move_maybe", b: "p3_move_no", note: "想搬 vs 决定不搬",
    aMatch: [["搬去", "搬過去", "同美玲住"]], bMatch: [["唔搬", "不搬"]]}],
  P4_tell_all: [{a: "p4_sister", b: "p4_divorce", note: "没结婚 vs 离过婚",
    aMatch: [["冇結婚", "未婚", "沒有結婚", "單身"]],
    bMatch: [["離婚", "離咗婚", "婚姻"]]},
  {a: "p4_loan", b: "p4_loan_partial", note: "借五万未还 vs 还了两万",
    aMatch: [["未還", "五萬"]], bMatch: [["兩萬"]]},
  {a: "p4_phone1", b: "p4_phone2", note: "旧电话 vs 新电话",
    aMatch: [["9123"]], bMatch: [["6987"]]}],
};

const PROFILES = [P1, P2, P3, P4];

/**
 * Assign positions to planted lines without one: a stable pseudo-random
 * turn (hash of the id), so long sessions get some early and some late
 * lines. Only the last 10 elder turns fit the App's 20-message buffer
 * (lib/core/agent_context/agent_context_service.dart, bufferCap).
 */
function hash(s) {
  let h = 2166136261;
  for (const c of s) h = Math.imul(h ^ c.codePointAt(0), 16777619) >>> 0;
  return h;
}
for (const p of PROFILES) {
  p.sessions.forEach((s, i) => {
    s.index = i;
    s.date = dayKey(s.day);
    const taken = new Set(s.planted.filter((x) => x.pos !== undefined)
        .map((x) => x.pos));
    for (const x of s.planted.filter((y) => y.pos === undefined)) {
      let pos = hash(x.id) % s.turns;
      while (taken.has(pos)) pos = (pos + 1) % s.turns;
      taken.add(pos);
      x.pos = pos;
    }
  });
}

module.exports = {START, dayKey, weekday, PROFILES, CONTRADICTIONS};
