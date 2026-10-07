# 附录：t10_run1 逐条抽取结果与判定

标签：correct 对 / duplicate 重复但对 / wrong 值错 / wrong_date 日期错 / fabricated 编造或曲解 / forbidden_stored 不应记却记了 / unlisted_true 真实但不在标准答案。

## D01（P01，siu_yan，2026-10-07 10:15 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 稱呼 陳太 | 叫我陳太得啦 | name・normal・shared・active | correct | D01-F1 |
| 事实 | 居住地區 自己一個住喺深水埗 | 我自己一個住喺深水埗 | living・normal・shared・active | correct | D01-F2 |
| 事实 | 女兒探訪 阿欣逢禮拜日都會上嚟同陳太食飯 | 佢逢禮拜日都會上嚟同我食飯 | family・normal・shared・active | correct | D01-F4 |
| 事实 | 女兒居住地 個女阿欣住沙田 | 個女阿欣住沙田 | family・normal・shared・active | correct | D01-F3 |
| 跟进 | 陳太下個禮拜四要去覆診 | 下個禮拜四要去覆診 | 到期 2026-10-15・normal | correct | D01-FU1 gold 2026-10-15 |

## D02（P01，tung_tung，2026-10-07 11:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 腳唔好行唔到山 腳唔好，行唔到山 | 冇喎，我腳唔好，行唔到山㗎。 | health・sensitive・agent・pending_confirmation | correct | D02-F2 |
| 事实 | 鍾意睇粵劇 鍾意睇粵劇，最鍾意任白嗰啲 | 我唔睇波㗎，我鍾意睇粵劇，任白嗰啲最好睇。 | preference・normal・agent・active | correct | D02-F1 |
| 跟进 | 同樓下街坊陳師奶去高山劇場睇大戲 | 後日同樓下街坊陳師奶去高山劇場睇大戲。 | 到期 2026-10-09・normal | correct | D02-FU1 gold 2026-10-09 |
| 摘要 | 陳太同通通傾偈，講到自己鍾意睇粵劇，尤其任白嘅戲；腳唔好行唔到山；後日會同樓下街坊陳師奶去高山劇場睇大戲。 |  | normal | ok |  |

## D03（P01，ah_jan_ah_bak，2026-10-07 15:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 舊居 以前喺深水埗住咗四十年 | 我以前喺深水埗住咗四十年 | living・normal・shared・active | correct | D03-F3 |
| 事实 | 稱呼 陳太；以前街坊叫佢「陳姑娘」 | 叫我「陳姑娘」 | name・normal・shared・active | correct | D03-F4 |
| 事实 | 年齡 八十歲 | 八十先啱 | health・sensitive・agent・pending_confirmation | correct | D03-F2 |
| 事实 | 現居 上個月搬咗去沙田同阿欣一齊住 | 我上個月搬咗去沙田同阿欣一齊住 | living・normal・shared・active | correct | D03-F1 |
| 事实 | 買餸習慣 以前喺北河街買餸，檔主都識佢 | 以前喺北河街買餸，個個檔主都識我 | hobby・normal・agent・active | duplicate | D03-F4 |
| 摘要 | 陳太同陪伴者傾舊時深水埗嘅街坊生活，講到以前住咗四十年、北河街街市好熱鬧，檔主都叫佢「陳姑娘」。佢又提到上個月搬咗去沙田同阿欣一齊住。 |  | normal | ok |  |

## D04（P02，ah_jan_ah_bak，2026-10-07 09:40 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 志明探訪 志明有時會嚟探黃伯 | 志明有時會嚟 | family・normal・shared・active | correct | D04-F1 |
| 事实 | 稱呼 黃伯 | 叫我黃伯得啦 | name・normal・shared・active | duplicate | D04-F1 |
| 事实 | 兒子 有兩個仔：大仔志強喺英國，細仔志明住屯門 | 我有兩個仔，大仔志強喺英國，細仔志明住屯門 | family・normal・shared・active | correct | D04-F5 |
| 事实 | 妻子離世 妻子已離世，黃伯掛住佢，夜晚瞓唔着會喊 | 而家夜晚成日瞓唔着，諗起佢就喊 | family・sensitive・agent・pending_confirmation | correct | D04-F2 |
| 跟进 | 黃伯老婆死忌，會同家人一齊去拜佢 | 下個月十二號係我老婆死忌，我哋會一齊去拜佢 | 到期 2026-11-12・sensitive | correct | D04-FU1 gold 2026-11-12 |

## D05（P02，siu_yan，2026-10-07 14:00 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 志明聽日帶孫探訪 聽日志明會帶個孫嚟探佢 | 聽日志明會帶個孫嚟探我 | family・normal・shared・active | unlisted_true | 真实：老人确实说过；是带日期的计划又记成一条事实（跟进层另有一条）。严格口径不算对 |
| 事实 | 打完太極同老友飲茶 打完太極同啲老友飲咗杯茶 | 打完同啲老友飲咗杯茶 | event・normal・agent・active | correct | D05-F1 |
| 事实 | 早上打太極 今朝有去公園打太極 | 今朝有去公園打太極 | routine・normal・agent・active | duplicate | D05-F1 |
| 跟进 | 志明帶個孫嚟探黃伯 | 聽日志明會帶個孫嚟探我 | 到期 2026-10-08・normal | correct | D05-FU1 gold 2026-10-08 |

## D06（P02，tung_tung，2026-10-07 16:20 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D07（P03，siu_yan，2026-10-07 01:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 生日 後日生日，八十六歲 | 後日係我生日呀，八十六歲喇。 | event・normal・agent・active | correct | D07-F3 |
| 事实 | 稱呼 李婆婆 | 叫我李婆婆啦，大家都咁叫。 | name・normal・shared・active | correct | D07-F1 |
| 事实 | 教會探訪活動 呢個禮拜六教會有探訪活動，會去 | 呢個禮拜六教會有探訪活動，我都會去。 | event・normal・agent・active | correct | D07-F4 |
| 事实 | 家務助理 阿芳係家務助理，菲律賓人，好細心 | 阿芳係我嘅家務助理，菲律賓人，好細心。 | family・normal・shared・active | correct | D07-F2 |
| 跟进 | 阿芳陪李婆婆去街市買餸 | 聽日朝早九點阿芳陪我去街市買餸。 | 到期 2026-10-08・normal | correct | D07-FU1 gold 2026-10-08 |
| 跟进 | 李婆婆八十六歲生日 | 後日係我生日呀，八十六歲喇。 | 到期 2026-10-09・normal | correct | D07-FU2 gold 2026-10-09 |
| 跟进 | 李婆婆去教會探訪活動 | 呢個禮拜六教會有探訪活動，我都會去。 | 到期 2026-10-10・normal | correct | D07-FU3 gold 2026-10-10 |
| 摘要 | 李婆婆夜晚瞓唔着，同陪伴者傾偈。佢提到聽日朝早九點會由家務助理阿芳陪去街市買餸，又講到後日係自己八十六歲生日，同埋呢個禮拜六會去教會探訪活動。 |  | normal | ok |  |

## D08（P03，ah_jan_ah_bak，2026-10-07 10:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 老公職業 老公以前揸的士，日日夜晚先返屋企 | 我老公以前揸的士，日日夜晚先返屋企。 | family・normal・shared・active | correct | D08-F2 |
| 事实 | 工作經歷 後生喺製衣廠做車衣，做咗三十年 | 我後生都喺製衣廠做車衣，做咗三十年。 | event・normal・agent・active | correct | D08-F1 |
| 事实 | 出生地及來港時間 喺順德出世，十二歲先落嚟香港 | 我細個喺順德出世，十二歲先落嚟香港。 | living・normal・shared・active | correct | D08-F3 |
| 摘要 | 李婆婆講述自己細個喺順德出世，十二歲先落嚟香港，後生喺製衣廠做車衣三十年，老公以前揸的士。 |  | normal | ok |  |

## D09（P03，tung_tung，2026-10-07 13:00 HKT）

状态 done；丢弃 fact:quote_not_found

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 個孫教用手機影相 個孫教佢用手機影相 | 個孫教我用手機影，我好鍾意。 | family・normal・shared・active | correct | D09-F1 |
| 事实 | 報咗長者旅行團去大澳 月尾社區中心有長者旅行團去大澳，佢報咗名 | 月尾社區中心有長者旅行團去大澳，我報咗名。 | event・normal・agent・active | correct | D09-F3 |
| 事实 | 鍾意影相 鍾意用手機影相，今朝去公園影咗好多張紫荊花 | 我今朝去公園影花，用部手機影咗好多張紫荊花。 | hobby・normal・agent・active | duplicate | D09-F1 |
| 跟进 | 社區中心長者旅行團去大澳 | 月尾社區中心有長者旅行團去大澳，我報咗名。 | 到期 2026-10-31・normal | correct | D09-FU1 gold 2026-10-25..2026-10-31 |
| 摘要 | 李婆婆今朝去公園用手機影紫荊花，話個孫教佢用手機影相，佢好鍾意。佢又提到月尾報咗社區中心長者旅行團去大澳。 |  | normal | ok |  |

## D10（P04，tung_tung，2026-10-07 10:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 同住家人 同老婆阿玲兩個人住 | 同老婆阿玲兩個人住 | family・normal・shared・active | correct | D10-F3 |
| 事实 | 稱呼 張伯，舊同事叫佢阿張 | 叫我張伯得喇，舊同事都叫我阿張 | name・normal・shared・active | correct | D10-F1 |
| 事实 | 興趣 最鍾意行山 | 我最鍾意行山 | hobby・normal・agent・active | correct | D10-F4 |
| 事实 | 居住地區 住將軍澳 | 我住將軍澳 | living・normal・shared・active | correct | D10-F2 |
| 跟进 | 去深圳飲外甥嘅喜酒 | 兩個禮拜後要去深圳飲外甥嘅喜酒 | 到期 2026-10-21・normal | correct | D10-FU2 gold 2026-10-19..2026-10-25 |
| 跟进 | 同幾個舊同事去行麥理浩徑第二段 | 下個禮拜一同幾個舊同事去行麥理浩徑第二段 | 到期 2026-10-12・normal | correct | D10-FU1 gold 2026-10-12 |
| 摘要 | 張伯同通通傾偈，講到自己住將軍澳，同老婆阿玲兩個人住，最鍾意行山，下個禮拜一同舊同事去行麥理浩徑第二段，兩個禮拜後去深圳飲外甥嘅喜酒。 |  | normal | ok |  |

## D11（P04，siu_yan，2026-10-07 15:00 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 被電話詐騙兩萬蚊 早排俾人打電話呃咗兩萬蚊，已經報警，但覺得應該追唔返。 | 早排俾人打電話呃咗兩萬蚊，好嬲。 | event・sensitive・agent・pending_confirmation | correct | D11-F2 |
| 事实 | 糖尿病 上個禮拜驗身驗出有糖尿病，醫生叫佢戒口，唔可以食甜嘢。 | 上個禮拜驗身驗出有糖尿病，醫生叫我戒口，唔可以食甜嘢。 | health・sensitive・agent・pending_confirmation | correct | D11-F1 |
| 事实 | 最鍾意食蛋撻 最鍾意食蛋撻。 | 我最鍾意食蛋撻㗎。 | preference・normal・agent・active | correct | D11-F3 |
| 跟进 | 下個月五號要再去抽血。 | 下個月五號要再去抽血。 | 到期 2026-11-05・normal | correct | D11-FU1 gold 2026-11-05 |

## D12（P04，ah_jan_ah_bak，2026-10-07 11:45 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 結婚年數 結婚四十五年。 | 四十五年喇 | family・normal・shared・active | correct | D12-F3 |
| 事实 | 老婆名 老婆叫阿琼，唔係阿玲。 | 我老婆唔係叫阿玲，係叫阿琼 | family・normal・shared・active | correct | D12-F1 |
| 事实 | 孫女阿瑤同住 孫女阿瑤同住，讀緊大學。 | 個孫女阿瑤都同我哋住，佢讀緊大學 | family・normal・shared・active | correct | D12-F2 |
| 事实 | 老婆煮餸 老婆煮得一手好菜。 | 佢煮得一手好菜 | family・normal・shared・active | correct | D12-F5 |
| 摘要 | 張伯講到屋企同住嘅人，提到孫女阿瑤讀緊大學，又更正老婆嘅名係阿琼，話結婚四十五年，讚佢煮得一手好菜。 |  | normal | ok |  |

## D13（P05，siu_yan，2026-10-07 09:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 日常照顧 每朝推丈夫落樓下茶樓飲早茶 | 我每朝都會推佢落樓下茶樓飲早茶 | routine・normal・agent・active | correct | D13-F4 |
| 事实 | 居住地區 住黃大仙 | 我住黃大仙 | living・normal・shared・active | correct | D13-F2 |
| 事实 | 稱呼 何太 | 叫我何太啦 | name・normal・shared・active | correct | D13-F1 |
| 事实 | 丈夫健康狀況 丈夫前年中風之後要坐輪椅 | 佢前年中風之後要坐輪椅 | family・sensitive・agent・pending_confirmation | correct | D13-F3 |
| 跟进 | 帶丈夫去做物理治療 | 下個禮拜三要帶佢去做物理治療 | 到期 2026-10-14・normal | correct | D13-FU1 gold 2026-10-14 |
| 摘要 | 何太居於黃大仙，日常要照顧中風後坐輪椅的丈夫，每朝會推丈夫落樓下茶樓飲早茶。她提到下個禮拜三要帶丈夫去做物理治療。 |  | normal | ok |  |

## D14（P05，tung_tung，2026-10-07 12:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D15（P05，ah_jan_ah_bak，2026-10-07 17:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 後生做酒樓點心 後生喺酒樓做點心，做咗二十幾年。 | 我後生喺酒樓做點心，做咗二十幾年。 | hobby・normal・agent・active | correct | D15-F1 |
| 事实 | 只有一個女喺澳洲墨爾本 得一個女，佢喺澳洲墨爾本。 | 冇呀，我得一個女，佢喺澳洲墨爾本。 | family・normal・shared・active | correct | D15-F2 |
| 事实 | 每個禮拜六晚同女視像 每個禮拜六晚都會同個女視像。 | 每個禮拜六晚都會同我視像。 | routine・normal・agent・active | correct | D15-F3 |
| 摘要 | 何太講到後生喺酒樓做點心二十幾年，又提到自己只有一個女喺澳洲墨爾本，每個禮拜六晚會同佢視像。陪伴者提議下個禮拜去探舊時酒樓同事，何太話再算。 |  | normal | ok |  |

## D16（P06，ah_jan_ah_bak，2026-10-07 10:10 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 後生做海員 後生時同人一齊做海員，跟船去過日本、新加坡 | 我哋後生一齊做海員，跟船去過好多地方，日本、新加坡都去過。 | event・normal・agent・active | correct | D16-F3 |
| 事实 | 稱呼 劉國華，大家都叫佢華叔 | 我叫劉國華，不過大家都叫我華叔。 | name・normal・shared・active | correct | D16-F1 |
| 事实 | 孫俊仔 有個孫叫俊仔 | 我個孫俊仔下個禮拜日會嚟同我飲茶。 | family・normal・shared・active | correct | D16-F5 |
| 事实 | 捉象棋 好鍾意捉象棋，以前日日喺公園同人捉 | 我好鍾意捉象棋，以前日日喺公園同人捉。 | hobby・normal・agent・active | correct | D16-F4 |
| 跟进 | 孫俊仔嚟同華叔飲茶 | 我個孫俊仔下個禮拜日會嚟同我飲茶。 | 到期 2026-10-11・normal | wrong_date | D16-FU1 gold 2026-10-18 |

## D17（P06，siu_yan，2026-10-07 03:15 HKT）

状态 done；丢弃 summary:safety_concern

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 去老人中心剪頭髮 聽日下晝去老人中心剪頭髮 | 聽日下晝我要去老人中心剪頭髮 | event・normal・agent・active | unlisted_true | 真实：老人确实说过；是带日期的计划又记成一条事实（跟进层另有一条）。严格口径不算对 |
| 跟进 | 去老人中心剪頭髮 | 聽日下晝我要去老人中心剪頭髮 | 到期 2026-10-08・normal | correct | D17-FU1 gold 2026-10-08 |

## D18（P06，tung_tung，2026-10-07 14:40 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 眼矇睇唔清棋子 眼矇，睇唔清啲棋子 | 不過而家眼矇，睇唔清啲棋子 | health・sensitive・agent・pending_confirmation | correct | D18-F2 |
| 事实 | 以前嗜好捉象棋 以前鍾意捉象棋 | 我以前鍾意捉象棋 | hobby・normal・agent・active | correct | D18-F3 |
| 事实 | 日日聽收音機講古 日日聽收音機講古 | 改咗日日聽收音機講古 | routine・normal・agent・active | correct | D18-F1 |
| 跟进 | 去換身份證 | 一個月後要去換身份證 | 到期 2026-11-07・normal | correct | D18-FU1 gold 2026-11-04..2026-11-09 |
| 摘要 | 華叔同通通傾偈，講到自己以前鍾意捉象棋，但而家眼矇睇唔清棋子，所以改為日日聽收音機講古。佢又提到一個月後要去換身份證。 |  | normal | ok |  |

## D19（P07，tung_tung，2026-10-07 11:20 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 老公 有老公，會慶祝老公九十大壽 | 慶祝我老公九十大壽 | family・normal・shared・active | correct | D19-F2 |
| 事实 | 家人聚會 十一月三號成家人聚會，慶祝老公九十大壽 | 十一月三號仲有成家人聚會，慶祝我老公九十大壽 | event・normal・agent・active | duplicate | D19-F2 |
| 事实 | 長洲玩 下個禮拜六同班姊妹去長洲玩 | 下個禮拜六同班姊妹去長洲玩 | event・normal・agent・active | correct | D19-F4 |
| 事实 | 睇眼科 下星期二要去睇眼科 | 下星期二又要去睇眼科 | health・sensitive・agent・pending_confirmation | unlisted_true | 真实：老人确实说过；是带日期的计划又记成一条事实（跟进层另有一条）。严格口径不算对 |
| 事实 | 稱呼 吳婆婆 | 叫我吳婆婆 | name・normal・shared・active | correct | D19-F1 |
| 事实 | 契女 有契女，會去飲契女嘅喜酒 | 大後日要去飲契女嘅喜酒 | family・normal・shared・active | correct | D19-F3 |
| 跟进 | 同班姊妹去長洲玩 | 下個禮拜六同班姊妹去長洲玩 | 到期 2026-10-17・normal | correct | D19-FU3 gold 2026-10-17 |
| 跟进 | 去飲契女嘅喜酒 | 大後日要去飲契女嘅喜酒 | 到期 2026-10-10・normal | correct | D19-FU1 gold 2026-10-10 |
| 跟进 | 成家人聚會，慶祝老公九十大壽 | 十一月三號仲有成家人聚會，慶祝我老公九十大壽 | 到期 2026-11-03・normal | correct | D19-FU4 gold 2026-11-03 |
| 跟进 | 去睇眼科 | 下星期二又要去睇眼科 | 到期 2026-10-13・normal | correct | D19-FU2 gold 2026-10-13 |
| 摘要 | 吳婆婆講到自己近排好忙，提到會去飲契女嘅喜酒、睇眼科、同姊妹去長洲玩，以及十一月三號成家人聚會慶祝老公九十大壽。 |  | normal | ok |  |

## D20（P07，siu_yan，2026-10-07 16:00 HKT）

状态 done；丢弃 fact:quote_not_found、summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 個仔冇聯絡 個仔成個月冇打過電話嚟，覺得好孤獨 | 個仔成個月冇打過電話嚟，覺得好孤獨 | family・sensitive・agent・pending_confirmation | correct | D20-F1 |
| 事实 | 高血壓食藥 有高血壓，日日要食藥，有時都唔記得食 | 我有高血壓，日日要食藥，有時都唔記得食 | health・sensitive・agent・pending_confirmation | correct | D20-F2 |
| 跟进 | 去街坊會攞免費飯盒 | 過多三日我要去街坊會攞免費飯盒 | 到期 2026-10-10・normal | correct | D20-FU1 gold 2026-10-10 |

## D21（P07，ah_jan_ah_bak，2026-10-07 10:45 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 阿爸係漁民 阿爸係漁民，成日出海 | 阿爸係漁民，成日出海 | family・normal・shared・active | correct | D21-F2 |
| 事实 | 細個住鴨脷洲 細個喺鴨脷洲大 | 我細個喺鴨脷洲大 | living・normal・shared・active | correct | D21-F1 |

## D22（P08，siu_yan，2026-10-07 08:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 居住地區 住觀塘嘅公屋 | 我住觀塘嘅公屋 | living・normal・shared・active | correct | D22-F2 |
| 事实 | 台灣旅行 下個月初同太太去台灣旅行，太太想去日月潭 | 下個月初我同太太去台灣旅行，佢一路都想去日月潭 | event・normal・agent・active | correct | D22-F5 |
| 事实 | 孫女結婚 今個週末孫女結婚 | 呢個週末我孫女結婚 | event・normal・agent・active | correct | D22-F6 |
| 事实 | 養狗 養咗隻狗叫豆豆 | 我隻狗豆豆 | family・normal・shared・active | correct | D22-F3 |
| 事实 | 稱呼 鄭伯 | 叫我鄭伯 | name・normal・shared・active | correct | D22-F1 |
| 事实 | 每日散步 日日朝早六點帶狗豆豆去散步 | 日日朝早六點我都會帶我隻狗豆豆去散步 | routine・normal・agent・active | correct | D22-F4 |
| 跟进 | 鄭伯同太太去台灣旅行 | 下個月初我同太太去台灣旅行 | 到期 2026-11-01・normal | correct | D22-FU1 gold 2026-11-01..2026-11-07 |
| 跟进 | 鄭伯孫女結婚 | 呢個週末我孫女結婚 | 到期 2026-10-10・normal | correct | D22-FU2 gold 2026-10-10..2026-10-11 |
| 摘要 | 鄭伯講咗自己住觀塘公屋，每日朝早六點帶狗豆豆散步，下個月初會同太太去台灣旅行，今個週末孫女結婚。 |  | normal | ok |  |

## D23（P08，tung_tung，2026-10-07 13:10 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D24（P08，ah_jan_ah_bak，2026-10-07 15:15 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 豆豆離世 豆豆上個禮拜走咗，佢十二歲。 | 豆豆上個禮拜走咗，佢十二歲 | family・sensitive・agent・pending_confirmation | correct | D24-F1 |
| 事实 | 屋企好靜 屋企冇咗豆豆好靜，朝早都唔知做咩好。 | 屋企冇咗佢好靜，朝早都唔知做咩好 | living・normal・shared・active | unlisted_true | 真实：老人原话，不在标准答案里（丧宠后的感受，属敏感边界） |
| 跟进 | 同太太帶豆豆啲骨灰去海邊撒。 | 下個禮拜四我同太太會帶佢啲骨灰去海邊撒 | 到期 2026-10-15・normal | correct | D24-FU1 gold 2026-10-15 |
| 摘要 | 鄭伯提到豆豆上個禮拜走咗，佢十二歲，屋企冇咗佢好靜，朝早都唔知做咩好。鄭伯計劃下個禮拜四同太太帶豆豆啲骨灰去海邊撒。 |  | normal | ok |  |

## D25（P09，tung_tung，2026-10-07 10:00 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 居住地區 柴灣 | 我住柴灣 | living・normal・shared・active | correct | D25-F2 |
| 事实 | 整老婆餅 識整老婆餅，好出名，街坊都搶住要 | 我整嘅老婆餅好出名㗎，街坊都搶住要 | hobby・normal・agent・active | correct | D25-F1 |
| 事实 | 稱呼 蘇太 | 叫我蘇太得啦 | name・normal・shared・active | correct | D25-F3 |

## D26（P09，siu_yan，2026-10-07 05:45 HKT）

状态 done；丢弃 fact:quote_not_found、summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 女兒升職 個女升咗職 | 今晚個女請我去食飯，佢升咗職。 | family・normal・shared・active | correct | D26-F1 |
| 事实 | 長者中心義工 禮拜五照舊去長者中心做義工，教人整餅 | 禮拜五我照舊去長者中心做義工，教人整餅。 | routine・normal・agent・active | correct | D26-F2 |
| 事实 | 早起習慣 五點幾就醒咗，覺得老人家冇覺瞓 | 係呀，五點幾就醒咗，老人家冇覺瞓。 | routine・normal・agent・active | correct | D26-F3 |
| 事实 | 今晚與女兒食飯 今晚個女請食飯 | 今晚個女請我去食飯 | event・normal・agent・active | unlisted_true | 真实：老人确实说过；是带日期的计划又记成一条事实（跟进层另有一条）。严格口径不算对 |
| 事实 | 覆診 下個月十號要去覆診 | 下個月十號又要去覆診。 | health・sensitive・agent・pending_confirmation | unlisted_true | 真实：老人确实说过；是带日期的计划又记成一条事实（跟进层另有一条）。严格口径不算对 |
| 跟进 | 去長者中心做義工，教人整餅 | 禮拜五我照舊去長者中心做義工，教人整餅。 | 到期 2026-10-09・normal | correct | D26-FU2 gold 2026-10-09 |
| 跟进 | 去覆診 | 下個月十號又要去覆診。 | 到期 2026-11-10・normal | correct | D26-FU3 gold 2026-11-10 |

## D27（P09，ah_jan_ah_bak，2026-10-07 12:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 結婚年齡 二十歲結婚 | 唔係，係二十歲，我記錯咗。 | event・normal・agent・active | correct | D27-F1 |
| 事实 | 老公職業 以前做巴士司機，揸咗三十年巴士 | 佢以前做巴士司機，揸咗三十年巴士。 | family・normal・shared・active | correct | D27-F2 |
| 事实 | 仔女數目 有三個仔女 | 我有三個仔女。 | family・normal・shared・active | correct | D27-F3 |
| 事实 | 仔女孝順 兩個仔女好孝順，成日返嚟探佢 | 我兩個仔女都好孝順，成日返嚟探我。 | family・normal・shared・active | duplicate | D27-F3 |
| 摘要 | 蘇太講到結婚時嘅年紀，起初話十八歲，之後更正為二十歲。佢提到老公以前做巴士司機，揸咗三十年巴士，又話有三個仔女，其中兩個仔女好孝順，成日返嚟探佢。 |  | normal | ok |  |

## D28（P10，ah_jan_ah_bak，2026-10-07 11:00 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 工作 以前喺深水埗開士多，開咗四十年 | 我以前喺深水埗開士多，開咗四十年 | event・normal・agent・active | correct | D28-F4 |
| 事实 | 年齡 九十歲 | 我今年九十歲喇 | family・normal・shared・active | correct | D28-F2 |
| 事实 | 稱呼 馮伯 | 叫我馮伯 | name・normal・shared・active | correct | D28-F1 |
| 事实 | 女兒 個女美玲住喺隔籬座，日日過嚟幫佢煮飯 | 個女美玲住喺我隔籬座，日日都過嚟幫我煮飯 | family・normal・shared・active | correct | D28-F3 |

## D29（P10，tung_tung，2026-10-07 15:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D30（P10，siu_yan，2026-10-07 19:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 請姨姨煮飯 美玲話會請個姨姨嚟幫馮伯煮飯。 | 佢話會請個姨姨嚟幫我煮飯。 | living・normal・shared・active | correct | D30-F2 |
| 事实 | 美玲搬遷 美玲下個禮拜要搬去天水圍，以後冇咁方便過嚟。 | 美玲話下個禮拜要搬去天水圍，以後冇咁方便過嚟。 | family・normal・shared・active | correct | D30-F1 |
| 事实 | 曾孫出世 十二月頭馮伯個曾孫出世，佢做太公。 | 十二月頭我個曾孫就出世喇，我做太公喇！ | family・normal・shared・active | correct | D30-F3 |
| 跟进 | 馮伯曾孫出世 | 十二月頭我個曾孫就出世喇 | 到期 2026-12-01・normal | correct | D30-FU1 gold 2026-12-01..2026-12-10 |
| 跟进 | 美玲下個禮拜搬去天水圍 | 美玲話下個禮拜要搬去天水圍 | 到期 2026-10-14・normal | correct | D30-FU2 gold 2026-10-12..2026-10-18 |
| 摘要 | 馮伯提到美玲下個禮拜要搬去天水圍，之後會請姨姨嚟幫佢煮飯；佢又講到十二月頭曾孫出世，自己做太公。 |  | normal | ok |  |

