# 附录：t10_run4 逐条抽取结果与判定

标签：correct 对 / duplicate 重复但对 / wrong 值错 / wrong_date 日期错 / fabricated 编造或曲解 / forbidden_stored 不应记却记了 / unlisted_true 真实但不在标准答案。

## D01（P01，siu_yan，2026-10-07 10:15 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 女兒探訪 阿欣逢禮拜日都會上嚟同陳太食飯 | 佢逢禮拜日都會上嚟同我食飯 | family・normal・shared・active | correct | D01-F4 |
| 事实 | 居住狀況 自己一個住喺深水埗 | 我自己一個住喺深水埗 | living・normal・shared・active | correct | D01-F2 |
| 事实 | 女兒居住地 個女阿欣住沙田 | 個女阿欣住沙田 | family・normal・shared・active | correct | D01-F3 |
| 事实 | 稱呼 陳太 | 叫我陳太得啦 | name・normal・shared・active | correct | D01-F1 |
| 跟进 | 陳太下個禮拜四要去覆診 | 下個禮拜四要去覆診 | 到期 2026-10-15・normal | correct | D01-FU1 gold 2026-10-15 |

## D02（P01，tung_tung，2026-10-07 11:00 HKT）

状态 done；丢弃 fact:plan_is_followup

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 腳部狀況：行唔到山 腳唔好，行唔到山 | 我腳唔好，行唔到山㗎 | health・sensitive・agent・pending_confirmation | correct | D02-F2 |
| 事实 | 興趣：睇粵劇 鍾意睇粵劇，最鍾意任白（任劍輝、白雪仙）嘅戲 | 我鍾意睇粵劇，任白嗰啲最好睇 | hobby・normal・agent・active | correct | D02-F1 |
| 跟进 | 陳太同樓下街坊陳師奶去高山劇場睇大戲 | 後日同樓下街坊陳師奶去高山劇場睇大戲 | 到期 2026-10-09・normal | correct | D02-FU1 gold 2026-10-09 |
| 摘要 | 陳太同通通傾偈，講到自己鍾意睇粵劇，特別係任白嘅戲。佢提到後日會同樓下街坊陳師奶去高山劇場睇大戲。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D03（P01，ah_jan_ah_bak，2026-10-07 15:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 年齡 八十歲 | 我今年七十九……唔係唔係，八十先啱，人老咗記性差。 | health・sensitive・agent・pending_confirmation | correct | D03-F2 |
| 事实 | 舊居 以前喺深水埗住咗四十年 | 我以前喺深水埗住咗四十年 | living・normal・shared・active | correct | D03-F3 |
| 事实 | 搬遷 上個月搬咗去沙田同阿欣一齊住 | 我上個月搬咗去沙田同阿欣一齊住 | event・normal・agent・active | correct | D03-F1 |
| 事实 | 舊稱呼 以前喺北河街買餸，個個檔主都識我，叫我「陳姑娘」 | 以前喺北河街買餸，個個檔主都識我，叫我「陳姑娘」 | name・normal・shared・active | correct | D03-F4 |
| 事实 | 居住狀況 上個月搬咗去沙田同阿欣一齊住 | 我上個月搬咗去沙田同阿欣一齊住 | living・normal・shared・active・更新 | duplicate | D03-F1 |
| 摘要 | 陳太同陪伴者傾舊時深水埗街坊生活，講到以前住深水埗四十年、北河街街市好熱鬧，檔主叫她「陳姑娘」。她提到上個月已搬去沙田同女兒阿欣一齊住，並更正自己年齡為八十歲。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D04（P02，ah_jan_ah_bak，2026-10-07 09:40 HKT）

状态 done；丢弃 fact:plan_is_followup、summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 睡眠及情緒 夜晚成日瞓唔着，諗起老婆就喊 | 而家夜晚成日瞓唔着，諗起佢就喊 | health・sensitive・agent・pending_confirmation | correct | D04-F4 |
| 事实 | 細仔 細仔志明住屯門，有時會嚟探佢 | 細仔志明住屯門 | family・normal・shared・active | correct | D04-F6 |
| 事实 | 大仔 大仔志強喺英國 | 大仔志強喺英國 | family・normal・shared・active | correct | D04-F5 |
| 事实 | 稱呼 黃伯 | 叫我黃伯得啦 | name・normal・shared・active | correct | D04-F1 |
| 跟进 | 同兩個仔一齊去拜老婆 | 下個月十二號係我老婆死忌，我哋會一齊去拜佢 | 到期 2026-11-12・sensitive | correct | D04-FU1 gold 2026-11-12 |

## D05（P02，siu_yan，2026-10-07 14:00 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 晨運習慣 今朝去公園打太極，之後同老友飲茶 | 今朝有去公園打太極，打完同啲老友飲咗杯茶。 | routine・normal・agent・active | correct | D05-F1 |
| 跟进 | 細仔志明帶孫嚟探黃伯 | 聽日志明會帶個孫嚟探我。 | 到期 2026-10-08・normal | correct | D05-FU1 gold 2026-10-08 |

## D06（P02，tung_tung，2026-10-07 16:20 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D07（P03，siu_yan，2026-10-07 01:30 HKT）

状态 done；丢弃 fact:plan_is_followup、fact:plan_is_followup、summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 睡眠習慣 夜晚瞓唔着，覺得老人家少覺 | 瞓唔着呀。 | routine・sensitive・agent・pending_confirmation | correct | D07-F5 |
| 事实 | 稱呼 李婆婆 | 叫我李婆婆啦，大家都咁叫。 | name・normal・shared・active | correct | D07-F1 |
| 事实 | 家務助理 阿芳係家務助理，菲律賓人，好細心 | 阿芳係我嘅家務助理，菲律賓人，好細心。 | family・normal・shared・active | correct | D07-F2 |
| 跟进 | 李婆婆去教會探訪活動 | 呢個禮拜六教會有探訪活動，我都會去。 | 到期 2026-10-10・normal | correct | D07-FU3 gold 2026-10-10 |
| 跟进 | 李婆婆八十六歲生日 | 後日係我生日呀，八十六歲喇。 | 到期 2026-10-09・normal | correct | D07-FU2 gold 2026-10-09 |
| 跟进 | 阿芳陪李婆婆去街市買餸 | 聽日朝早九點阿芳陪我去街市買餸。 | 到期 2026-10-08・normal | correct | D07-FU1 gold 2026-10-08 |

## D08（P03，ah_jan_ah_bak，2026-10-07 10:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 出生地及來港 喺順德出世，十二歲先落嚟香港 | 我細個喺順德出世，十二歲先落嚟香港。 | event・normal・agent・active | correct | D08-F3 |
| 事实 | 稱呼 李婆婆 | 係呀，我喺香港出世，成世都喺香港。 | name・normal・shared・active・更新 | unlisted_true | 值「李婆婆」是对的（D07 讲过），但引文是「喺香港出世」，对不上；属更新同类事实，值不变，不影响注入。严格口径不算对 |
| 事实 | 老公職業 老公以前揸的士，日日夜晚先返屋企 | 我老公以前揸的士，日日夜晚先返屋企。 | family・normal・shared・active | correct | D08-F2 |
| 事实 | 工作經歷 後生喺製衣廠做車衣，做咗三十年 | 我後生都喺製衣廠做車衣，做咗三十年。 | hobby・normal・agent・active | correct | D08-F1 |
| 摘要 | 李婆婆講述自己細個喺順德出世，十二歲先落嚟香港，後生喺製衣廠做車衣三十年，老公以前揸的士。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D09（P03，tung_tung，2026-10-07 13:00 HKT）

状态 done；丢弃 fact:plan_is_followup

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 鍾意用手機影相 鍾意用手機影相，今朝去公園影咗好多張紫荊花，係個孫教佢用手機影。 | 我今朝去公園影花，用部手機影咗好多張紫荊花。 | hobby・normal・agent・active | correct | D09-F1 |
| 跟进 | 社區中心長者旅行團去大澳 | 月尾社區中心有長者旅行團去大澳，我報咗名。 | 到期 2026-10-31・normal | correct | D09-FU1 gold 2026-10-25..2026-10-31 |
| 摘要 | 李婆婆今朝去公園用手機影紫荊花，話係個孫教佢用手機影相，佢好鍾意。佢又提到月尾報咗社區中心長者旅行團去大澳。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D10（P04，tung_tung，2026-10-07 10:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 同住家人 同老婆阿玲兩個人住 | 同老婆阿玲兩個人住 | family・normal・shared・active | correct | D10-F3 |
| 事实 | 稱呼 張伯，舊同事叫佢阿張 | 叫我張伯得喇，舊同事都叫我阿張 | name・normal・shared・active | correct | D10-F1 |
| 事实 | 居住地區 住將軍澳 | 我住將軍澳 | living・normal・shared・active | correct | D10-F2 |
| 事实 | 興趣 最鍾意行山 | 我最鍾意行山 | hobby・normal・agent・active | correct | D10-F4 |
| 跟进 | 去深圳飲外甥嘅喜酒 | 兩個禮拜後要去深圳飲外甥嘅喜酒 | 到期 2026-10-21・normal | correct | D10-FU2 gold 2026-10-19..2026-10-25 |
| 跟进 | 同幾個舊同事去行麥理浩徑第二段 | 下個禮拜一同幾個舊同事去行麥理浩徑第二段 | 到期 2026-10-12・normal | correct | D10-FU1 gold 2026-10-12 |
| 摘要 | 張伯同通通傾偈，講到自己住將軍澳，同老婆阿玲兩個人住，最鍾意行山，下個禮拜一同舊同事去行麥理浩徑第二段，兩個禮拜後去深圳飲外甥嘅喜酒。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D11（P04，siu_yan，2026-10-07 15:00 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 鍾意食蛋撻 最鍾意食蛋撻 | 我最鍾意食蛋撻㗎 | preference・normal・agent・active | correct | D11-F3 |
| 事实 | 糖尿病 上個禮拜驗身驗出有糖尿病，醫生叫佢戒口，唔可以食甜嘢 | 上個禮拜驗身驗出有糖尿病，醫生叫我戒口，唔可以食甜嘢 | health・sensitive・agent・pending_confirmation | correct | D11-F1 |
| 事实 | 被電話詐騙兩萬蚊 早排俾人打電話呃咗兩萬蚊，已經報咗警 | 早排俾人打電話呃咗兩萬蚊，好嬲 | event・sensitive・agent・pending_confirmation | correct | D11-F2 |
| 跟进 | 下個月五號要再去抽血 | 下個月五號要再去抽血 | 到期 2026-11-05・normal | correct | D11-FU1 gold 2026-11-05 |

## D12（P04，ah_jan_ah_bak，2026-10-07 11:45 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 同住家人 同老婆阿琼、孫女阿瑤三個人住；阿瑤讀緊大學 | 其實我屋企唔止兩個人住，個孫女阿瑤都同我哋住，佢讀緊大學 | family・normal・shared・active・更新 | correct | D12-F1 |
| 事实 | 結婚年數 結婚四十五年 | 四十五年喇 | family・normal・shared・active | correct | D12-F3 |
| 事实 | 老婆名字 老婆叫阿琼，唔係阿玲 | 我老婆唔係叫阿玲，係叫阿琼，之前講錯咗 | family・normal・shared・active・更新 | duplicate | D12-F1 |
| 摘要 | 張伯更正同住家人資料，指孫女阿瑤同住並讀大學，又更正老婆名字為阿琼，並提到結婚四十五年。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D13（P05，siu_yan，2026-10-07 09:00 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 丈夫健康狀況 丈夫前年中風之後要坐輪椅 | 佢前年中風之後要坐輪椅 | family・sensitive・agent・pending_confirmation | correct | D13-F3 |
| 事实 | 稱呼 何太 | 叫我何太啦 | name・normal・shared・active | correct | D13-F1 |
| 事实 | 居住地區 住黃大仙 | 我住黃大仙 | living・normal・shared・active | correct | D13-F2 |
| 事实 | 每朝飲早茶 每朝都會推丈夫落樓下茶樓飲早茶 | 我每朝都會推佢落樓下茶樓飲早茶 | routine・normal・agent・active | correct | D13-F5 |
| 跟进 | 帶丈夫去做物理治療 | 下個禮拜三要帶佢去做物理治療 | 到期 2026-10-14・sensitive | correct | D13-FU1 gold 2026-10-14 |

## D14（P05，tung_tung，2026-10-07 12:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D15（P05，ah_jan_ah_bak，2026-10-07 17:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 同女兒視像 每個禮拜六晚都會同女兒視像 | 每個禮拜六晚都會同我視像。 | routine・normal・agent・active | correct | D15-F3 |
| 事实 | 後生職業 後生喺酒樓做點心，做咗二十幾年 | 我後生喺酒樓做點心，做咗二十幾年。 | hobby・normal・agent・active | correct | D15-F1 |
| 事实 | 子女 只有一個女，喺澳洲墨爾本 | 冇呀，我得一個女，佢喺澳洲墨爾本。 | family・normal・shared・active | correct | D15-F2 |
| 摘要 | 何太講述自己後生喺酒樓做點心二十幾年，又提到只有一個女喺澳洲墨爾本，每個禮拜六晚會視像。陪伴者建議去探舊同事，何太話再算。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容（陪伴者的建议写明是陪伴者提的，老人没答应） |

## D16（P06，ah_jan_ah_bak，2026-10-07 10:10 HKT）

状态 done；丢弃 fact:plan_is_followup、summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 捉象棋 好鍾意捉象棋，以前日日喺公園同人捉 | 我好鍾意捉象棋，以前日日喺公園同人捉。 | hobby・normal・agent・active | correct | D16-F4 |
| 事实 | 後生做海員 後生一齊做海員，跟船去過日本、新加坡 | 我哋後生一齊做海員，跟船去過好多地方，日本、新加坡都去過。 | event・normal・agent・active | correct | D16-F3 |
| 事实 | 稱呼 劉國華，大家都叫佢華叔 | 我叫劉國華，不過大家都叫我華叔。 | name・normal・shared・active | correct | D16-F1 |
| 跟进 | 孫俊仔嚟同華叔飲茶 | 我個孫俊仔下個禮拜日會嚟同我飲茶。 | 到期 2026-10-11・normal | wrong_date | D16-FU1 gold 2026-10-18 |

## D17（P06，siu_yan，2026-10-07 03:15 HKT）

状态 done；丢弃 fact:plan_is_followup、summary:safety_concern

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 跟进 | 去老人中心剪頭髮 | 聽日下晝我要去老人中心剪頭髮 | 到期 2026-10-08・normal | correct | D17-FU1 gold 2026-10-08 |

## D18（P06，tung_tung，2026-10-07 14:40 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 日日聽收音機講古 改咗日日聽收音機講古 | 改咗日日聽收音機講古 | routine・normal・agent・active | correct | D18-F1 |
| 事实 | 以前嗜好捉象棋 以前鍾意捉象棋，而家眼矇睇唔清啲棋子，冇點捉 | 我以前鍾意捉象棋，不過而家眼矇，睇唔清啲棋子，冇點捉喇 | hobby・sensitive・agent・pending_confirmation | correct | D18-F2 |
| 事实 | 眼矇 眼矇，睇唔清啲棋子 | 而家眼矇，睇唔清啲棋子 | health・sensitive・agent・pending_confirmation | duplicate | D18-F2 |
| 跟进 | 去換身份證 | 一個月後要去換身份證 | 到期 2026-11-07・normal | correct | D18-FU1 gold 2026-11-04..2026-11-09 |

## D19（P07，tung_tung，2026-10-07 11:20 HKT）

状态 done；丢弃 fact:plan_is_followup、fact:plan_is_followup

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 稱呼 吳婆婆 | 叫我吳婆婆 | name・normal・shared・active | correct | D19-F1 |
| 事实 | 老公 有老公，今年九十大壽 | 慶祝我老公九十大壽 | family・normal・shared・active | correct | D19-F2 |
| 事实 | 契女 有一個契女 | 飲契女嘅喜酒 | family・normal・shared・active | correct | D19-F3 |
| 跟进 | 成家人聚會，慶祝老公九十大壽 | 十一月三號仲有成家人聚會，慶祝我老公九十大壽 | 到期 2026-11-03・normal | correct | D19-FU4 gold 2026-11-03 |
| 跟进 | 去睇眼科 | 下星期二又要去睇眼科 | 到期 2026-10-13・normal | correct | D19-FU2 gold 2026-10-13 |
| 跟进 | 去飲契女嘅喜酒 | 大後日要去飲契女嘅喜酒 | 到期 2026-10-10・normal | correct | D19-FU1 gold 2026-10-10 |
| 跟进 | 同班姊妹去長洲玩 | 下個禮拜六同班姊妹去長洲玩 | 到期 2026-10-17・normal | correct | D19-FU3 gold 2026-10-17 |
| 摘要 | 吳婆婆講到自己近期好忙，提到會去飲契女嘅喜酒、睇眼科、同姊妹去長洲玩，以及十一月三號成家人聚會慶祝老公九十大壽。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容（「睇眼科」是约诊，决策 0009 不算敏感） |

## D20（P07，siu_yan，2026-10-07 16:00 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 高血壓 有高血壓，日日要食藥，有時唔記得食 | 我有高血壓，日日要食藥，有時都唔記得食 | health・sensitive・agent・pending_confirmation | correct | D20-F2 |
| 事实 | 個仔 有一個仔，成個月冇打過電話嚟 | 個仔成個月冇打過電話嚟 | family・sensitive・agent・pending_confirmation | correct | D20-F1 |
| 跟进 | 去街坊會攞免費飯盒 | 過多三日我要去街坊會攞免費飯盒 | 到期 2026-10-10・normal | correct | D20-FU1 gold 2026-10-10 |

## D21（P07，ah_jan_ah_bak，2026-10-07 10:45 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 童年住處 細個喺鴨脷洲大 | 我細個喺鴨脷洲大 | living・normal・shared・active | correct | D21-F1 |
| 事实 | 阿爸職業 阿爸係漁民，成日出海 | 阿爸係漁民，成日出海 | family・normal・shared・active | correct | D21-F2 |

## D22（P08，siu_yan，2026-10-07 08:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 稱呼 鄭伯 | 叫我鄭伯 | name・normal・shared・active | correct | D22-F1 |
| 事实 | 寵物 養咗隻狗叫豆豆 | 我隻狗豆豆 | family・normal・shared・active | correct | D22-F3 |
| 事实 | 太太 有太太 | 我同太太去台灣旅行 | family・normal・shared・active | correct | D22-F5 |
| 事实 | 居住地區 住觀塘嘅公屋 | 我住觀塘嘅公屋 | living・normal・shared・active | correct | D22-F2 |
| 事实 | 孫女 有孫女 | 我孫女結婚 | family・normal・shared・active | correct | D22-F6 |
| 事实 | 每日散步 日日朝早六點帶狗豆豆去散步 | 日日朝早六點我都會帶我隻狗豆豆去散步 | routine・normal・agent・active | correct | D22-F4 |
| 跟进 | 同太太去台灣旅行，去日月潭 | 下個月初我同太太去台灣旅行，佢一路都想去日月潭 | 到期 2026-11-01・normal | correct | D22-FU1 gold 2026-11-01..2026-11-07 |
| 跟进 | 孫女結婚 | 呢個週末我孫女結婚 | 到期 2026-10-10・normal | correct | D22-FU2 gold 2026-10-10..2026-10-11 |
| 摘要 | 鄭伯講咗自己住觀塘公屋，每日朝早六點帶狗豆豆散步，又提到下個月初同太太去台灣旅行，以及呢個週末孫女結婚。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D23（P08，tung_tung，2026-10-07 13:10 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D24（P08，ah_jan_ah_bak，2026-10-07 15:15 HKT）

状态 done；丢弃 summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 寵物 養咗隻狗叫豆豆，豆豆上個禮拜走咗，十二歲 | 豆豆上個禮拜走咗，佢十二歲 | family・sensitive・agent・pending_confirmation・更新 | correct | D24-F1 |
| 跟进 | 同太太帶豆豆啲骨灰去海邊撒 | 下個禮拜四我同太太會帶佢啲骨灰去海邊撒 | 到期 2026-10-15・sensitive | correct | D24-FU1 gold 2026-10-15 |

## D25（P09，tung_tung，2026-10-07 10:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 居住地區 柴灣 | 我住柴灣 | living・normal・shared・active | correct | D25-F2 |
| 事实 | 整老婆餅 識整老婆餅，好出名，街坊都搶住要 | 我整嘅老婆餅好出名㗎，街坊都搶住要 | hobby・normal・agent・active | correct | D25-F1 |
| 事实 | 稱呼 蘇太 | 叫我蘇太得啦 | name・normal・shared・active | correct | D25-F3 |
| 摘要 | 蘇太同陪伴者傾偈，提到自己整老婆餅好出名，街坊都搶住要；又講到自己住柴灣，並叫對方稱呼自己做蘇太。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D26（P09，siu_yan，2026-10-07 05:45 HKT）

状态 done；丢弃 fact:plan_is_followup、fact:plan_is_followup、fact:plan_is_followup、summary:sensitive

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 睡眠習慣 五點幾就醒咗，覺得老人家冇覺瞓 | 係呀，五點幾就醒咗，老人家冇覺瞓。 | routine・normal・agent・active | correct | D26-F3 |
| 跟进 | 蘇太去覆診 | 下個月十號又要去覆診。 | 到期 2026-11-10・normal | correct | D26-FU3 gold 2026-11-10 |
| 跟进 | 蘇太去長者中心做義工教人整餅 | 禮拜五我照舊去長者中心做義工，教人整餅。 | 到期 2026-10-09・normal | correct | D26-FU2 gold 2026-10-09 |
| 跟进 | 蘇太今晚同個女食飯 | 今晚個女請我去食飯，佢升咗職。 | 到期 2026-10-07・normal | correct | D26-FU1 gold 2026-10-07 |

## D27（P09，ah_jan_ah_bak，2026-10-07 12:00 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 老公職業 以前做巴士司機，揸咗三十年巴士 | 佢以前做巴士司機，揸咗三十年巴士。 | family・normal・shared・active | correct | D27-F2 |
| 事实 | 結婚年齡 二十歲結婚 | 唔係，係二十歲，我記錯咗。 | event・normal・agent・active | correct | D27-F1 |
| 事实 | 仔女關係 兩個仔女好孝順，成日返嚟探佢 | 我兩個仔女都好孝順，成日返嚟探我。 | family・normal・shared・active | correct | D27-F3 |
| 事实 | 仔女數目 有三個仔女 | 我有三個仔女。 | family・normal・shared・active | duplicate | D27-F3 |
| 摘要 | 蘇太講返自己二十歲結婚，老公以前做巴士司機三十年，有三個仔女，其中兩個成日返嚟探佢。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

## D28（P10，ah_jan_ah_bak，2026-10-07 11:00 HKT）

状态 done；丢弃 summary:safety_turns

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 事实 | 工作經歷 以前喺深水埗開士多，開咗四十年 | 我以前喺深水埗開士多，開咗四十年。 | event・normal・agent・active | correct | D28-F4 |
| 事实 | 稱呼 馮伯 | 叫我馮伯。 | name・normal・shared・active | correct | D28-F1 |
| 事实 | 年齡 九十歲 | 我今年九十歲喇。 | family・normal・shared・active | correct | D28-F2 |
| 事实 | 女兒 女兒美玲住喺隔籬座，日日過嚟幫他煮飯 | 個女美玲住喺我隔籬座，日日都過嚟幫我煮飯。 | family・normal・shared・active | correct | D28-F3 |

## D29（P10，tung_tung，2026-10-07 15:30 HKT）

状态 done；丢弃 无

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|

## D30（P10，siu_yan，2026-10-07 19:30 HKT）

状态 done；丢弃 fact:plan_is_followup、fact:plan_is_followup

| 类型 | 内容 | 原话 | 敏感/范围/状态 | 判定 | 对应答案 / 说明 |
|---|---|---|---|---|---|
| 跟进 | 曾孫十二月頭出世 | 十二月頭我個曾孫就出世喇 | 到期 2026-12-01・normal | correct | D30-FU1 gold 2026-12-01..2026-12-10 |
| 跟进 | 女兒美玲下個禮拜搬去天水圍 | 美玲話下個禮拜要搬去天水圍 | 到期 2026-10-14・normal | correct | D30-FU2 gold 2026-10-12..2026-10-18 |
| 摘要 | 馮伯同陪伴者傾偈，提到女兒美玲下個禮拜要搬去天水圍，之後會請姨姨嚟幫佢煮飯；又講到十二月頭曾孫出世，自己會做太公。 |  | normal | ok | 逐句对过原话：忠实，无编造，无安全或敏感内容 |

